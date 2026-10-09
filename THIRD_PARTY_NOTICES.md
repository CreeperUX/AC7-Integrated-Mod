# Attribution and licensing

## Project foundation and thanks

**AC7 Integrated Mod is a port of [AC8 Integrated Mod](https://github.com/CreeperUX/AC8-Integrated-Mod) to ACE COMBAT 7.** AC8 Integrated Mod is developed from [FletcherMiya/AC8-Mouse-Aim](https://github.com/FletcherMiya/AC8-Mouse-Aim). We thank FletcherMiya and the upstream contributors for developing and sharing the mouse-flight foundation used by both projects.

This repository is independently maintained. Attribution does not imply upstream endorsement of our modifications, and upstream copyright and license notices remain in place.

## Licenses

Original integration code and modifications are provided under the root MIT license. Third-party material keeps its own license and copyright notice.

| Component | Origin / license |
|---|---|
| AC8 Mouse Aim base | [FletcherMiya/AC8-Mouse-Aim](https://github.com/FletcherMiya/AC8-Mouse-Aim); upstream LICENSE declares CC0 1.0. See `package/licenses/MouseAim/LICENSE.txt` and `package/licenses/MouseAim-CC0.txt` |
| MouseFlight reference | [brihernandez/MouseFlight](https://github.com/brihernandez/MouseFlight), MIT, Brian Hernandez; see `package/licenses/MouseFlight-MIT.txt` |
| MinHook / bundled HDE | [TsudaKageyu/minhook](https://github.com/TsudaKageyu/minhook), BSD-style notices preserved in `native/src/vendor/minhook/LICENSE.txt` and `package/licenses/MinHook-BSD.txt` |
| RE-UE4SS | [UE4SS-RE/RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS), MIT, Narknon and contributors; runtime 3.0.1 Beta (Git 48e7edfe) shipped in the release package; see `package/licenses/UE4SS-MIT.txt` |
| Fonts | Chakra Petch SemiBold and Share Tech Mono, SIL Open Font License 1.1; license files next to the fonts (`package/ui/creeperux/fonts`, `ui-fonts` in the payload) |
| CreeperUX UI Kit | [CreeperUX/CreeperUX-UI-Kit](https://github.com/CreeperUX/CreeperUX-UI-Kit) 2.4.0 design tokens; provenance in `package/ui/creeperux/SOURCE.json` |

The missile rules are the numeric rules of AC8 Integrated Mod's missile module, mapped onto AC7's player weapon classes. That module originated from research around the user-provided **AC8-PropNav v1.1** release, attributed in its supplied reference to **麦糊**; this repository records that provenance and does not import the original third-party distribution.

No ACE COMBAT game executable, mesh, texture, audio, extracted asset package, decryption key, memory dump, raw save or raw personal flight recording is included. Class names, field names, memory layout notes and numeric settings are used to reference the user's own installed game.

The root license does not replace the individual third-party licenses. Preserve this file and all applicable license files in redistributed packages. This is an unofficial community project and is not affiliated with the game publisher or the upstream projects.
