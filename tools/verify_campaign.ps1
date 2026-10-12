param([string]$Godot = "godot", [switch]$PublishVerified, [switch]$VisualReview,
    [string[]]$Suites = @("music_transitions", "run", "bucket_elevator", "resizable_supports", "functional_mechanisms", "campaign_rules", "puzzle_workflow", "campaign_chapters", "campaign"))

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot
$originalTestData = $env:MARBLE_ENGINEER_TEST_DATA
$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testDirectory = Join-Path $temporaryRoot ("marble-engineer-tests-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $testDirectory | Out-Null
$env:MARBLE_ENGINEER_TEST_DATA = $testDirectory
if ($VisualReview) { $Suites = @("campaign_chapters") }
Write-Output "Temporary test saves and logs: $testDirectory (removed on exit; APPDATA unchanged)."
try {
    foreach ($suite in (@("check_gdscript") + $Suites)) {
        $log = Join-Path $testDirectory "$suite-verification.log"
        $scriptPath = if ($suite -eq "check_gdscript") { "tools/check_gdscript.gd" } else { "tests/$suite.gd" }
        $arguments = @("--headless", "--path", $projectPath, "--log-file", (Join-Path $testDirectory "$suite-engine.log"), "--fixed-fps", "120", "--script", $scriptPath)
        if ($VisualReview -and $suite -eq "campaign_chapters") {
            $arguments = @("--path", $projectPath, "--log-file", (Join-Path $testDirectory "$suite-engine.log"), "--script", $scriptPath, "--", "--visual-review")
        }
        if ($suite -eq "campaign") {
            $arguments += @("--", "--negative")
            if ($PublishVerified) { $arguments += "--publish-verified" }
        }
        & $Godot @arguments *> $log
        $suiteExitCode = $LASTEXITCODE
        $lines = Get-Content -LiteralPath $log
        $runtimeErrors = @($lines | Where-Object { $_ -match "^(SCRIPT ERROR:|ERROR:)" -and $_ -notmatch "Failed to read the root certificate store" })
        $lines | Where-Object { $_ -match "GDSCRIPT CHECK:|RESULT:|TESTS:|RULES:|WORKFLOW:|CHAPTERS:|CAMPAIGN FAILURES:|: PASS|: FAIL" } | Write-Output
        if ($suiteExitCode -ne 0 -or $runtimeErrors.Count -gt 0) {
            $lines | Write-Output
            throw "$suite failed (exit $suiteExitCode). See output above."
        }
    }
    Write-Output "All campaign and existing construction verification gates passed."
} finally {
    $env:MARBLE_ENGINEER_TEST_DATA = $originalTestData
    # Delete only this invocation's uniquely named directory under the OS temp root.
    $resolvedTestDirectory = [System.IO.Path]::GetFullPath($testDirectory)
    if ([System.IO.Path]::GetDirectoryName($resolvedTestDirectory) -ne $temporaryRoot.TrimEnd('\', '/') -or
        [System.IO.Path]::GetFileName($resolvedTestDirectory) -notmatch '^marble-engineer-tests-[0-9a-f]{32}$') {
        throw "Refusing cleanup outside the expected test directory: $resolvedTestDirectory"
    }
    $testFiles = @(Get-ChildItem -LiteralPath $resolvedTestDirectory -File -Recurse)
    $testBytes = ($testFiles | Measure-Object -Property Length -Sum).Sum
    Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force
    Write-Output "Removed temporary test data ($($testFiles.Count) files, $testBytes bytes)."
}
