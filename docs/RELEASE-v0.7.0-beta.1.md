# v0.7.0-beta.1 — 安装版、一键更新与附加 Mod

**Beta 测试版。仅限离线单人，禁止带 Mod 进入线上或多人模式。**

这一版把 AC7 移植的能力对齐到 AC8 Integrated 2.5.0。

## 主要内容

- **安装版**：运行 `AC7-Integrated-Setup-v0.7.0-beta.1.exe`，按当前用户安装，不需要管理员权限，从开始菜单打开 **AC7 Integrated**。已经在用便携版时，安装程序会导入它的设置、键位、安装内容、路径和附加 Mod，并把游戏中的 Mod 交给安装版管理。
- **一键更新**：启动器右上角“检查更新”，可选每天自动检查。更新包经过数字签名和哈希校验，游戏中的 Mod 随之更新；设置、键位和附加 Mod 都会保留，还能回退到上一版本。
- **检查并修复**：每次启动前自动核对程序文件；“检查并修复”还会恢复游戏中缺失或被改动的 Mod 文件、损坏的设置和开始菜单项。从启动器启动游戏时，鼠标飞控就绪会显示 `[READY]`，没就绪会说明原因。
- **附加 Mod**：在启动器中管理其他 UE4SS Mod。添加 zip 或文件夹（可以直接拖进窗口），启用、停用或删除，自动同步到游戏；你手动放进游戏的 Mod 不受影响。
- **WAR 成为默认飞控**，F4 仍可切换到 PEACE。之前保存的 PEACE 会改为 WAR 一次。
- **飞行记录开关**：默认只保留文本日志，需要分析问题时在启动器中勾选“保存飞行记录”。
- **独立的启动程序** `AC7 Integrated.exe`：打开启动器时不再出现命令行窗口，任务栏显示 AC7 图标，可以固定到任务栏。

飞控手感与 v0.6.0-beta.1 相同（WAR 13.8）；也包含 v0.6.1 的 HDR 准星修复（ReShade／RenoDX 下准星正常显示）。

## 安装

- **安装版（推荐）**：下载并运行 **AC7-Integrated-Setup-v0.7.0-beta.1.exe**。安装程序没有代码签名证书，Windows 可能提示“Windows 已保护你的电脑”，点击“更多信息”→“仍要运行”。
- **便携版**：下载 **AC7-Integrated-v0.7.0-beta.1.zip**，解压到游戏目录之外，双击 `AC7 Integrated.exe`。

在启动器中选择安装内容，关闭游戏后点击“安装／更新”，然后从 Steam 启动游戏，操纵类型选专家（Expert）。

需要：ACE COMBAT 7: SKIES UNKNOWN（Steam，Build 9855922），Windows 10／11 64 位。

## English summary

**Beta release. Offline single-player only.**

This release brings the AC7 port up to AC8 Integrated 2.5.0.

- **Installed app**: `AC7-Integrated-Setup-v0.7.0-beta.1.exe` installs per user (no administrator rights) with a Start menu entry. It can import the portable package you already use and take over the mod it installed.
- **One-click updates**: "检查更新" in the launcher, optional daily check. Updates are signature- and hash-verified, the mod in the game is updated with them, settings, key bindings and extra mods are kept, and the previous version stays available for rollback.
- **Check and repair**: program files are checked before every start; "检查并修复" also restores missing or changed mod files in the game, damaged settings and the Start menu entry. Launching from the launcher reports `[READY]`, or the reason when the mod is not ready.
- **Extra UE4SS mods**: add from a zip or folder (drag and drop), enable, disable or remove; changes sync into the game, and mods you placed by hand are left alone.
- **WAR is the default flight control** (F4 still switches to PEACE); a saved PEACE moves to WAR once.
- **Flight-record switch**: text log only by default; tick "保存飞行记录" when a problem needs analysis.
- **Launcher as its own application** `AC7 Integrated.exe`: no console window, the AC7 icon on the taskbar, can be pinned.

Flight control is unchanged from v0.6.0-beta.1 (WAR 13.8); the v0.6.1 HDR reticle fix (ReShade/RenoDX) is included.

Requires ACE COMBAT 7: SKIES UNKNOWN (Steam, build 9855922) on 64-bit Windows 10/11.
