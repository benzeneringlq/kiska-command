Kiska Command / 基斯卡行动：单机小队战术 FPS 原型。默认中文，可切换英文，使用 Godot 4.5.2 + C++17。

## 下载与运行

| 文件名后缀 | 平台 | 启动 |
| --- | --- | --- |
| `windows.zip` | Windows x86_64 | 解压后打开 `KiskaCommand.exe` |
| `linux.tar.gz` | Linux x86_64（在 Ubuntu 22.04 构建） | 解压后运行 `./KiskaCommand.x86_64` |
| `macos-intel.zip` | macOS Intel | 解压后打开 `Kiska Command.app` |
| `macos-arm64.zip` | macOS Apple Silicon（M1/M2/M3/M4 等） | 解压后打开 `Kiska Command.app` |

下载对应平台的游戏压缩包，无需安装 Godot 或编译工具。请完整解压并保留随包文件。GitHub 自动附带的 Source code 是源码，不是游戏安装包。`SHA256SUMS.txt` 可用于校验下载。

macOS 包使用 ad-hoc 本地签名，未做苹果公证；系统可能拦截首次启动。确认来自本仓库后，可在“系统设置 → 隐私与安全性”选择“仍要打开”。Windows 包也未使用付费代码签名证书。

## 本版内容

- 基斯卡岛地形、小队战斗、车辆与运输机装载。
- 轻按 Q 下达上下文意图，长按 Q 查看详细命令。
- 队员自动安排驾驶员、登车、驾驶、到达下车；运输机装卸串联为完整任务。
- WASD 移动、鼠标开火/瞄准、B 背包、M 地图、E 上下车、F11 全屏。

每个包在对应平台编译 C++ 扩展，通过核心检查，并运行导出游戏的 184 项集成检查后才发布。无显示器的自动检查不代表所有显卡与驱动已验证。模型、导航和飞行仍为原型实现。

English: Download the archive for your OS/CPU, extract the entire folder and launch the game. Godot is bundled. macOS builds are ad-hoc signed, not notarized. This is a playable prototype, not a finished commercial game. See the repository README for controls and limitations.
