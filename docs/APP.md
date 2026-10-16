# 安装版（0.7.0 起）

[返回说明首页](../README.md) · [附加 Mod](EXTRA-MODS.md)

0.7.0 起提供 Windows 安装程序。安装版与便携版的游戏内功能完全相同，另外可以：

- 从 GitHub 一键更新，可选每天自动检查新版本；
- 每次启动前自动核对程序文件，损坏时自动恢复；“检查并修复”处理更多问题；
- 设置、键位、附加 Mod 和备份集中保存在安装目录的 `data` 中，更新时保留；
- 回退到上一版本，在 Windows“应用”中卸载。

## 安装

1. 从 GitHub 发布页下载 **AC7-Integrated-Setup-v0.7.0-beta.1.exe**。安装程序没有代码签名证书，Windows 可能提示“Windows 已保护你的电脑”，点击“更多信息”→“仍要运行”。
2. 退出游戏后运行。程序安装到当前用户的 `%LOCALAPPDATA%\Programs\AC7 Integrated`，不需要管理员权限，不改动 Steam 设置。
3. 游戏里的 Mod 是由便携版安装的时，安装程序会找到那个便携版，询问是否导入设置、键位、安装内容、游戏和 Steam 路径以及附加 Mod，并询问是否把游戏中的 Mod 交给安装版管理（先备份存档和原文件，逐个校验）。便携版本身不会被改动，确认安装版正常后可以自行删除。
4. 从开始菜单打开 **AC7 Integrated**（独立应用，不会出现命令行窗口；任务栏显示 AC7 图标，可以固定到任务栏）。游戏中还没有安装 Mod 时，点击“自动定位”，选择安装内容，再点击“安装／更新”。

之后照常从 Steam 启动游戏，或在启动器中点击“从 Steam 启动”：控制台会先核对程序文件和游戏中的 Mod（需要时更新到当前版本），启动游戏后在鼠标飞控就绪时显示 `[READY]`；没有就绪时显示 `[NOT READY]` 和原因。安全软件拦截或隔离了刚安装的 DLL 时，会在启动游戏前说明。

## 更新

- **检查更新**（启动器右上角）：发现新版本后确认，启动器会关闭，控制台中下载、校验并安装，游戏中的 Mod 随之更新（需要关闭游戏），完成后自动重新打开启动器。
- **每天自动检查更新**（设置与维护，默认开启）：打开启动器时最多每天检查一次，有新版本时版本标签显示“可更新到 …”。
- 只从本项目的 GitHub 发布页下载（包括 Beta 测试版）。安装前核对更新清单的数字签名（RSA-3072）和安装包的 SHA-256，并逐个核对包内文件；只接受比当前更新的版本。游戏运行中或上一次安装没有完成时不会更新。
- 设置、键位、附加 Mod 和备份都会保留。程序保留当前和上一个版本。
- 只读取 GitHub 发布信息和下载安装包，不上传任何数据。

## 检查并修复

启动器“设置与维护”→“检查并修复”：

| 检查 | 处理 |
|---|---|
| 程序文件是否完整 | 从本地已校验的安装包恢复；本地没有时从 GitHub 重新下载同一版本 |
| 设置、键位、安装范围能否读取 | 备份原文件，恢复默认，并保留仍然有效的设置 |
| 游戏中的 Mod 文件 | 缺失或被改动的文件恢复为当前版本（被改动的先备份）；版本较旧时更新 |
| 开始菜单和卸载项 | 缺失时恢复 |

检查结束后可以输入 R 回退到上一版本。

## 数据位置

安装目录下的 `data` 文件夹：

- `MouseAim-Settings.ini`、`Keybindings.ini`、`features.ini`、`game-path.txt`、`steam-path.txt`：设置；
- `ue4ss-mods`：附加 UE4SS Mod 的 Mod 库，`ue4ss-mods-removed`：删除或替换下来的 Mod；
- `backups`、`cleanup-backups`：安装与卸载前的存档和原文件备份；
- `sessions`、`diagnostics`：收集的日志和错误诊断（含个人数据，不要直接分享）；
- `update-cache`：已校验的安装包，用于离线修复。

## 停用 Mod 与卸载

- **多人前**：启动器“停用 Mod（多人前）”，游戏以原版启动；“启用 Mod（单人）”恢复。
- **卸载**：Windows 设置 → 应用 → 已安装的应用 → AC7 Integrated → 卸载。会先卸载游戏中由安装版管理的 Mod（先备份，被改动的文件保留）；`data` 默认保留，也可以选择一并删除。

## 便携版

zip 便携版继续提供，设置保存在包内。双击包里的 **AC7 Integrated.exe** 打开启动器（`Start-GUI.cmd` 仍然可用）。便携版也可以在启动器中“检查更新”，新版本需要手动下载。

## English summary

From 0.7.0 a Windows setup program installs AC7 Integrated per user in `%LOCALAPPDATA%\Programs\AC7 Integrated` (no administrator rights). If the mod in the game was installed by a portable package, setup can import that package's settings and take over the installed mod (save backup, every file verified); the portable package is only read. The launcher (Start menu: AC7 Integrated) checks GitHub for updates (manually, or at most once a day), verifies the RSA-3072 signed update manifest, the package SHA-256 and every file, installs only newer releases (pre-releases included), updates the mod in the game and keeps the previous version for rollback. Before every start the program files are checked and restored from the cached verified package; "检查并修复" (check and repair) also restores missing or changed mod files in the game, rebuilds unreadable settings with a backup and restores the Start menu entry. Launching from the launcher reports `[READY]` or the reason the mod is not ready. Player data lives in `data`. Uninstall from Windows Settings > Apps. The portable zip remains available. The setup program is not code-signed, so SmartScreen may ask for confirmation.
