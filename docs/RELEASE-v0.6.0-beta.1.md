# v0.6.0-beta.1 — AC7 首个公开测试版

**Beta 测试版。仅限离线单人，禁止带 Mod 进入线上或多人模式。**

## 主要内容

- **鼠标飞控**：采用 AC8 Integrated 2.4.2 的控制核心。WAR 模式基于还原的 AC7 飞行引擎做精确预测，机头走直线，鼠标停下后平滑改平，来回拖动时反应更快。按住方向键约 0.1–0.2 s 即接管，并接着按键的爬升继续；按 F4 可切换到经典的 PEACE 模式。
- **清晰准星**：鼠标圆环、机头参考准星（Alt+F7 开关）和头盔瞄准括号环由 GPU 在原生分辨率独立绘制，4K 下同样清晰。线宽可在「飞控设置 → 准星线宽」调整；游戏中修改 `config.ini` 的 `hud_line_width` 后按 F10 即时生效。
- **自由观察与头盔瞄准**：按住 C 自由观察、右键放大；F2 头盔瞄准，自由观察时括号环跟随视线。
- **导弹模块（可选）**：
  - **仅制导**：只把 30 种玩家导弹的比例引导前置量调到 AC8 规则，其余保持原版；
  - **完整强化**：AC8 完整导弹规则（标准导弹锁定 2.4 km，4AAM／6AAM 10 km，LAAM 20 km 等）。
  - 只在单人任务中生效，离开任务时恢复原值。
- **启动器**：一键安装／更新、停用／启用 Mod、飞控与键位设置；安装和卸载前自动备份存档，可接管已有的 AC7 鼠标飞控安装。

## 安装

1. 下载 **AC7-Integrated-v0.6.0-beta.1.zip**，解压到游戏目录之外的新文件夹。
2. 关闭游戏，运行 `Start-GUI.cmd`，选择安装内容后点击「安装／更新」。
3. 照常从 Steam 启动游戏，操纵类型选专家（Expert）。

需要：ACE COMBAT 7: SKIES UNKNOWN（Steam，Build 9855922），Windows 10／11 64 位。

## English summary

**Beta release. Offline single-player only.**

- **Mouse flight control** with the AC8 Integrated 2.4.2 core. WAR predicts on a reconstructed model of AC7's flight engine: straight nose paths, smooth levelling, quick reversals; a held key takes over after about 0.1-0.2 s and continues along the key ramp. F4 switches to the classic PEACE controller.
- **Sharp reticle**: mouse ring, nose reference gun cross (Alt+F7) and HMD bracket ring drawn by the GPU at native resolution; adjustable line width (settings, or `hud_line_width` in `config.ini` + F10).
- **Free look and HMD**: hold C to look around, right mouse to zoom; F2 HMD target selection follows the view in free look.
- **Optional missile module**: guidance-only tier (AC8 proportional-navigation lead on 30 player missiles) or the full AC8 rules (standard missile lock-on 2.4 km, 4AAM/6AAM 10 km, LAAM 20 km, ...), single-player missions only, stock values restored after a mission.
- **Launcher**: install/update, disable/enable, flight and key settings, automatic save backups.

Requires ACE COMBAT 7: SKIES UNKNOWN (Steam, build 9855922) on 64-bit Windows 10/11.
