# Changelog

## v0.7.0-beta.1 — 2026-10-15

Brings the AC7 port up to AC8 Integrated Mod 2.5.0.

- Installed app: setup program `AC7-Integrated-Setup-v<version>.exe` (IExpress, per user in `%LOCALAPPDATA%\Programs\AC7 Integrated`, no administrator rights), Start menu entry, uninstall from Windows Settings > Apps. Program versions in `versions\<v>`, player data in `data\`. Setup imports the portable package that installed the mod in the game (settings, key bindings, scope, paths, extra mods) and can take over the installed mod (save backup, journal, every file verified). The mod stays installed persistently in the game folder as before; the app brings it to the current version after updates, rollbacks and repairs.
- Updates from the GitHub releases of this repository (pre-releases included): RSA-3072 signed `update-manifest.json` (its own AC7 key), zip size and SHA-256, every file checked against `FILES.sha256`; only newer versions; refused while the game runs or an install is unfinished. Current and previous versions kept, rollback. Launcher: "检查更新" and an optional daily check.
- Self-repair: program files checked before every start and restored from the cached verified package; "检查并修复" also restores changed or deleted mod files in the game (changed ones backed up first), rebuilds unreadable settings with a backup and restores the Start menu entry and uninstall registration.
- Launch through the app: quick repair, the installed mod brought to the current version, Steam start, then `[READY]` / `[NOT READY]` with the reason from `UE4SS.log`; DLLs removed or changed after installation (security software) are reported before the game starts.
- Native launcher `AC7 Integrated.exe` (source/launcher, built with the .NET Framework C# compiler included in Windows; icon, version, asInvoker): the player tool as its own application. It hosts Host.ps1 -Action Gui (installed) or Launcher-GUI.ps1 (package) in its own process with the Windows PowerShell 5.1 engine, so the window, taskbar button, Alt+Tab and pinning show AC7 Integrated with its icon; no console window, a splash until the launcher appears. Window icons on the launcher and its dialogs; console windows titled "AC7 Integrated".
- WAR is the default flight control (`control_modes::default_mode=3`); a saved PEACE moves to WAR once (`migrations.json`, `war-default-0.7.0`), a later PEACE choice is kept.
- Extra UE4SS mods (launcher "附加 Mod"): add from a zip or folder (drag and drop; mod folders found by layout; loader DLLs and Pak assets not installed; unsafe paths and links refused), replace keeping the enabled state, enable/disable, remove to `ue4ss-mods-removed`. Changes are synced into the game's `ue4ss\Mods` with a record (`ue4ss\AC7-ExtraMods.json`) and an `enabled.txt`; only recorded, unchanged files are ever removed, and folders the player placed by hand are never overwritten. Uninstall removes the deployed copies and keeps the library. Bundles the UE4SS `shared` library (UEHelpers).
- Flight-record switch (launcher checkbox, `flight_recording` in the settings and `config.ini`, off by default): off writes no FE trace and no Shadow CSV, only the text log.
- Core from AC8 2.5.0 (pinned snapshot); flight control unchanged (WAR 13.8 with the 2.4.2 keyboard takeover).
- Tests: Test-ExtraMods (library, game sync, dialog, migration), Test-App (installed app end to end), Test-Launcher, modes_tests default.

## v0.6.1-beta.1 — 2026-10-12 (not released separately; included in v0.7.0-beta.1)

- GPU reticle works under HDR mods. ReShade/RenoDX hook every DXGI swap chain in the process, including the overlay's: RenoDX rewrote it to HDR10 (Direct2D could not draw, legacy markers) and ReShade's present pass made it opaque. The overlay no longer uses a swap chain: Direct2D draws into a BGRA canvas that is copied into a DirectComposition surface, which ReShade never sees; Windows composes it as SDR content on SDR and HDR desktops. New `test-overlay-host.cmd` checks on the real desktop that the overlay stays transparent, plain and with ReShade + RenoDX loaded.

## v0.6.0-beta.1 — 2026-10-09

First public beta of the AC7 port.

- Mouse flight control from AC8 Integrated Mod 2.4.2 (WAR 13.8): PEACE/WAR on F4; WAR predicts on a reconstructed model of AC7's flight engine and hooks the game's own input stage; War Thunder-style keyboard takeover with the 2.4.2 rule (engage at 0.3 while held, continue from the key ramp, hand back at 0.8).
- Reticle drawn on a GPU overlay (D3D11 + Direct2D + DirectComposition) at native resolution: ring, reference gun cross, HMD bracket ring, free-look ring and connector ticks with the AC8 2.4.1 geometry; `hud_line_width` (0.5-2) re-read by F10. The reticle can also be drawn inside the game HUD (`hud_renderer=3`).
- Free look with zoom, HMD target selection along the view, native/far camera, F1 panel and notices with bundled fonts.
- AC7Weapons missile module with two tiers (`features=guidance` / `features=full`), including AC7's VeryEasy_ parameter copies; stock values restored outside missions.
- Launcher and console tools: install/update with per-file verification and rollback, disable/enable, settings and key bindings, uninstall with backups, adoption of earlier AC7 mouse-aim installs.
