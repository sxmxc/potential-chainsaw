param([string]$Godot = "godot", [switch]$PublishVerified)

$ErrorActionPreference = "Stop"
$projectPath = Split-Path -Parent $PSScriptRoot
$originalAppData = $env:APPDATA
$testDirectory = Join-Path $projectPath ".local-user"
New-Item -ItemType Directory -Force -Path $testDirectory | Out-Null
New-Item -ItemType File -Force -Path (Join-Path $testDirectory ".gdignore") | Out-Null
$env:APPDATA = $testDirectory
$suites = @("run", "bucket_elevator", "resizable_supports", "functional_mechanisms", "campaign_rules", "puzzle_workflow", "campaign")
try {
    foreach ($suite in $suites) {
        $log = Join-Path $testDirectory "$suite-verification.log"
        $arguments = @("--headless", "--path", $projectPath, "--fixed-fps", "120", "--script", "tests/$suite.gd")
        if ($suite -eq "campaign") {
            $arguments += @("--", "--negative")
            if ($PublishVerified) { $arguments += "--publish-verified" }
        }
        & $Godot @arguments *> $log
        $suiteExitCode = $LASTEXITCODE
        $lines = Get-Content -LiteralPath $log
        $runtimeErrors = @($lines | Where-Object { $_ -match "^(SCRIPT ERROR:|ERROR:)" -and $_ -notmatch "Failed to read the root certificate store" })
        $lines | Where-Object { $_ -match "RESULT:|TESTS:|RULES:|WORKFLOW:|CAMPAIGN FAILURES:|: PASS|: FAIL" } | Write-Output
        if ($suiteExitCode -ne 0 -or $runtimeErrors.Count -gt 0) {
            throw "$suite failed (exit $suiteExitCode). Inspect $log`n$($runtimeErrors -join "`n")"
        }
    }
    Write-Output "All campaign and existing construction verification gates passed."
} finally {
    $env:APPDATA = $originalAppData
}
