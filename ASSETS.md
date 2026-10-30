# 素材来源

本项目的人物、枪械、建筑、载具、岩石与合成音效由代码生成；v0.4 地形采用下述 USGS 公开高程数据。

| 内容 | 生成位置 | 许可 |
| --- | --- | --- |
| 地形网格生成代码、岩石、建筑、沙袋、情报箱、撤离信标 | `game/scripts/battlefield.gd` | 本项目 MIT |
| 按类别生成的第一人称武器、瞄具、手套和枪口闪光 | `game/scripts/weapon_model.gd` | 本项目 MIT |
| 越野车、装甲运输车、运输直升机和架设机枪模型 | `game/scripts/vehicle_model.gd` | 本项目 MIT |
| 队友与敌人的低多边形模型 | `game/scripts/soldier.gd` | 本项目 MIT |
| 枪声、远处枪声、换弹声和提示音 | `game/scripts/field_audio.gd` | 本项目 MIT |
| 菜单、HUD、地图、图形与准星 | `game/scripts/interface.gd` | 本项目 MIT |

没有使用《闪点行动》原版资产，也没有下载外部的三维模型包或纹理包。

`game/data/weapons.json` 中的名称和数值是玩法配置。模型按武器类别搭建，没有为每种名称制作精确还原的独立模型。

## 中文字体

v0.2 为中文界面新增 **Noto Sans SC** 可变字体，这是第三方开源资源：

- 来源：[Google Fonts / Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc)
- 文件：`game/fonts/NotoSansSC.ttf`
- 许可：SIL Open Font License 1.1，全文保留在 `game/fonts/OFL.txt`。不适用本项目的 MIT 许可。
- 原始文件名：`NotoSansSC[wght].ttf`；只改了仓库内文件名，没有修改字体内容。
- SHA-256：`a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da`

Godot 与 godot-cpp 是引擎和绑定依赖，各自保留其发行包中的许可。

## 基斯卡岛真实地形（v0.4）

- 数据提供方：USGS National Map 3D Elevation Program (3DEP)。
- [高程服务](https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer)、[产品说明](https://www.usgs.gov/3d-elevation-program/about-3dep-products-services)、[USGS 公共领域说明](https://www.usgs.gov/faqs/are-usgs-reportspublications-copyrighted)。USGS 制作的数据属于美国公共领域，不改称本项目 MIT 资产。
- 导出日期：2026-10-30。UTM 60N / EPSG:32660，49152 m 方形区域，1025 × 1025 样本，48 m 输出采样间距，垂直比例 1:1。输出采样间距不等于数据源测绘精度。
- `game/data/terrain/kiska.f32`：小端 float32，北到南逐行，完整来源请求与 SHA-256 保留于同目录 `kiska.json`。
- `kiska_map.png` 是上述数据生成的设色阴影图，没有使用第三方地图瓦片或卫星影像。
- 零值海域替换为 -8 m 占位海床，不是真实水深；海岸线是 DEM 零高程附近的近似，不是独立高精度海岸矢量。营地、道路、机场和局部整平为原创虚构玩法内容。
- 导入工具：`tools/import_kiska.py`。运行游戏无需网络或 Python 地理工具。
- 地貌参考：[美国国家公园管理局基斯卡战场景观说明](https://www.nps.gov/articles/cultural-landscape-kiska.htm)。主要为苔原和裸岩，北部为火山；并非当前灰盒的现代营地布局。


## v0.5 植被与载具

- `game/scripts/tundra_vegetation.gd`、`game/shaders/vegetation.gdshader`：程序生成草丛、蕨状叶片、低矮灌木、风摆和距离渐隐。均为本项目 MIT 原创内容，没有下载外部植物包或贴图。
- `game/scripts/vehicle_model.gd`：升级后的程序载具，包括车轮、轮毂、驾驶舱和灯等。仍为低多边形原型美术，不宣称精确还原真实型号。


## v0.6 陆地物流与重型运输机

`game/scripts/vehicle_model.gd` 新增原创程序卡车、坦克和「擎天」运输机、货舱、坡道、舱内照明。`game/scripts/vehicle_logistics.gd` 中的减速伞和拖缆也由几何体生成。均为本项目 MIT 内容，无外部下载模型、原作地图资源或商用载具资产。
