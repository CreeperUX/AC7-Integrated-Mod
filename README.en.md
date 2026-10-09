# AC7 Integrated Mod — v0.6.0-beta.1

Beta release. **Offline single-player only; do not use online or in multiplayer.** AC7's multiplayer anti-cheat treats injected code as cheating; use "停用 Mod" (disable mod) in the launcher before playing online.

The mouse flight control of [AC8 Integrated Mod](https://github.com/CreeperUX/AC8-Integrated-Mod) 2.4.2, ported to ACE COMBAT 7: SKIES UNKNOWN (Steam, build 9855922). The mouse sets a direction and the mod coordinates the aircraft's attitude to fly to the ring. **F4** toggles two flight controllers:

- **WAR** (default): exact prediction on a reconstructed model of AC7's flight engine, with a War Thunder-style mouse-instructor structure: straight nose paths, smooth levelling once the mouse rests, and keyboard takeover after about 0.1-0.2 s of a held key;
- **PEACE**: the classic controller.

Also included:

- a reticle drawn by the GPU at native resolution (mouse ring, nose reference gun cross, HMD bracket ring), sharp at 4K, with adjustable line width;
- C free look with right-mouse zoom, F2 HMD target selection, F3 native/far camera;
- the optional AC7Weapons missile module with two tiers, **guidance only** (proportional-navigation lead) and **full** (the complete AC8 missile rules), active in single-player missions only;
- a graphical launcher for install/update, disabling/enabling the mod, flight and key settings, with save backups before install and uninstall.

Download the complete **AC7-Integrated-v0.6.0-beta.1.zip** from [Releases](https://github.com/CreeperUX/AC7-Integrated-Mod/releases/tag/v0.6.0-beta.1), not the Source code ZIP. The installer UI is Chinese. Extract it to a new folder outside the game, close the game, run **Start-GUI.cmd**, choose the scope and click "安装／更新" (install/update), then start the game from Steam as usual. Select the **Expert** control type in game.

Keys: F1 settings panel · F2 HMD · F3 camera · F4 WAR/PEACE · F7 HUD · Alt+F7 gun cross · F8 flight control on/off · F9 recenter · F10 reload config · hold C free look

[0.6.0-beta.1 changes](docs/RELEASE-v0.6.0-beta.1.md) · [Changelog](CHANGELOG.md)

Based on AC8 Integrated Mod, which is developed from [FletcherMiya/AC8-Mouse-Aim](https://github.com/FletcherMiya/AC8-Mouse-Aim). Thanks to the original author and contributors; [licenses and credits](THIRD_PARTY_NOTICES.md) are retained. This is an unofficial community project, not affiliated with the game publisher or the upstream projects.

[简体中文](README.md)
