# Changelog

## v0.6.0-beta.1 — 2026-10-09

First public beta of the AC7 port.

- Mouse flight control from AC8 Integrated Mod 2.4.2 (WAR 13.8): PEACE/WAR on F4; WAR predicts on a reconstructed model of AC7's flight engine and hooks the game's own input stage; War Thunder-style keyboard takeover with the 2.4.2 rule (engage at 0.3 while held, continue from the key ramp, hand back at 0.8).
- Reticle drawn on a GPU overlay (D3D11 + Direct2D + DirectComposition) at native resolution: ring, reference gun cross, HMD bracket ring, free-look ring and connector ticks with the AC8 2.4.1 geometry; `hud_line_width` (0.5-2) re-read by F10. The reticle can also be drawn inside the game HUD (`hud_renderer=3`).
- Free look with zoom, HMD target selection along the view, native/far camera, F1 panel and notices with bundled fonts.
- AC7Weapons missile module with two tiers (`features=guidance` / `features=full`), including AC7's VeryEasy_ parameter copies; stock values restored outside missions.
- Launcher and console tools: install/update with per-file verification and rollback, disable/enable, settings and key bindings, uninstall with backups, adoption of earlier AC7 mouse-aim installs.
