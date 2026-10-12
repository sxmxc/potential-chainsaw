# Native UI verification

Open `scenes/ui/sandbox_hud.tscn` in the editor to inspect the container hierarchy and its instantiated file, build and edit toolbars, toolbox and inspector. Open `scenes/ui/main_menu.tscn`, `scenes/ui/track_browser.tscn`, the scenes in `scenes/ui/dialogs/`, and `scenes/ui/widgets/piece_card.tscn` to edit their saved controls. All reference the shared project Theme, `resources/sandbox_theme.tres`.

Edit visual presets through the Theme editor. Change control layout through the scene inspector. Scripts bind existing named nodes and signals; toolbox filtering instantiates `piece_card.tscn`. `tools/create_theme.gd` is an optional offline generator; do not run it after hand-editing the Theme unless intentionally replacing those edits.

Regression command, with isolated test saves on Windows:

```powershell
$env:APPDATA = "$PWD/.local-user"
godot --headless --path . --fixed-fps 120 --script tests/run.gd
```

Result: 97 checks, zero failures. Both example tracks reach their finish through actual physics. Tests cover native Theme configuration/variations, dialogs, save/reopen and editing/history alongside the construction and simulation checks.

The actual main scene was rendered in seven states at three native resolutions. The captures in `docs/qa/` are original framebuffer images, not resized screenshots. `layout_evidence.json` records requested and actual resolution and bounds findings for all 21 captures. Visual review includes the inspector at 720p and settings at 1080p; inspector scrolling corrected the detected small-window overflow.

To repeat the graphical captures:

```powershell
godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --script tools/visual_qa.gd
```

Run the main project through the existing editor for Forward+ verification; avoid starting a second editor for import checks. The live editor/runtime is inspected through Hera. Standalone sandboxed engine processes can emit a Windows certificate-store initialization error unrelated to UI resource loading or gameplay.
