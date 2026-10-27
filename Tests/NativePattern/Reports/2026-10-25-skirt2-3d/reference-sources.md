# 双片裙 3D：输入保真与官方参照

本报告仅为私有研究预览。交互页面显示本项目实际求解网格；官方公开图是不同输入的定性参照，**没有同输入官方最终三维网格，不能宣称三维效果等价**。

## 官方二维输入

锁定 [GarmentCode 提交 d4496299](https://github.com/maria-korosteleva/GarmentCode/tree/d449629979028123a5c4dc9e732a2ec19b7fce31)，使用 [mean_all 人体](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/bodies/mean_all.yaml)、[默认设计](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/design_params/default.yaml)，设 `meta.bottom=Skirt2`、关闭上装及腰头。官方 fixture 是项目 `Tests/NativePattern/Fixtures/skirt-two-panel.json`；生成器会先核对上游提交与工作区代码。

默认双片裙 `rise=1`、`length=0.2`、`ruffle=1.3`、`flare=0`、`bottom_cut=0`。腰围 84.3338 cm、后腰围 39.1358 cm、腰臀高 23.4837 cm、派生腿长 85.2888 cm。前片宽为 `(84.3338−39.1358)×1.3=58.7574 cm`，后片宽为 `39.1358×1.3=50.87654 cm`。垂直裙长为 `23.4837+0.2×85.2888=40.54146 cm`。

| 原纸样指标 | 官方 fixture 独立测量 |
| --- | ---: |
| 腰口总长 | 109.63394000 cm |
| 下摆总长 | 109.63394000 cm |
| 垂直裙长 | 40.54146000 cm |
| 两片总面积 | 4444.71999315 cm² |
| 默认生成端点最大差 | 0 cm |

`flare` 是每片每侧增加的厘米数：两片总下摆相对腰口增加 `4×flare`，侧缝长为 `sqrt(垂直裙长²+flare²)`。它不是尺寸倍率。接缝保持前片边 3 ↔ 后片边 0、前片边 1 ↔ 后片边 2；前后片的腰口为边 2／边 1。默认官方平移是初始摆片，不是最终垂坠。

原始纸样的长度、面积、静止约束均来自平面四边形，按 100 cm/m 转换成求解单位。标准人体上的外向褶皱支撑环保留原腰口各网格边长；支撑腰围和原纸样腰口总长分开记录。该支撑是实验装配，没有模拟真实腰头、松紧带或抽褶缝制过程。

双片裙的拉伸／剪切距离约束逐一对应真实三角网格边。一个四边网格单元只保留实际剖分使用的一条对角线，使两个三角形可以沿公共边折叠；同时约束两条对角线会把平面四边形锁成刚性单元，阻碍抽褶展开。二阶距离弯曲约束另行保留为软近似，没有用垂坠姿态改写静止边长。

有裙摆增量时，梯形裁片的侧缝需要向外倾斜；虚拟腰口支撑把两组侧缝放在外向褶峰，避免把侧缝压在贴人体的褶谷。各段仍严格按原纸样腰口边长构造；前后片宽度不相等也不会被重置为各一半。下方初始化包络来自标准人体的实际水平截面，排除远离躯干的手臂／手部后包住躯干或双腿；围度不足的输入明确拒绝，不靠修改原纸样通过。

## 官方三维图与许可

原图从已有研究报告复制，未裁切或改绘：

| 本地图片 | 来源与归属 | SHA-256 |
| --- | --- | --- |
| `references/garmentcode-header.png` | [GarmentCode 官方示例](https://github.com/maria-korosteleva/GarmentCode/blob/main/assets/img/header.png)，Maria Korosteleva 等；仓库 MIT | `e3cd112937455057f16e3405d5f6c67380d6622cb2ee4b6d978c1c16d284855c` |
| `references/design2garmentcode-result-text.png` | [Design2GarmentCode 官方文字生成结果](https://style3d.github.io/design2garmentcode/static/images/result_text.png)，Feng Zhou 等；官网 CC BY-SA 4.0 | `3332c598b4901683d1b197a60bd6721946b4b7c8df34f351dca4658c5fc7c787` |

GarmentCode 图是多款成衣群像。Design2GarmentCode 图左侧是该方法、右侧是 DressCode 对照，其中环扇形裙片与连衣裙不是当前 Skirt2 的同输入结果。人物、面料、设计与相机未对齐；不能计算三维表面误差，也不能把公开图用于本 App 的人体或成衣素材。

[Design2GarmentCode 的官方实现](https://github.com/Style3D/design2garmentcode-impl#3-optional-enable-3-d-simulation)使用 GarmentCode 的定制 Warp 仿真后端，因此它们不是两个独立的物理求解器验证。本项目未引入该受限 Warp 实现作为产品依赖。

标准人体来自 MakeHuman CC0 固定来源，详细来源、哈希与许可见 App `GarmentCodeStandardBodySource.json`、`MakeHuman-CC0-LICENSE.txt` 与项目 `THIRD_PARTY_NOTICES.md`。人体是有限尺寸拟合，不是个人身体重建。碰撞场覆盖脚底到腰线上方 20 cm，距离场顶点穿入估计和末态布片交叉检查不等于完整或连续人体碰撞保证。

## 实际证据与复核范围

`comparison.json` 记录默认源几何差值、独立平面测量及所展示数据的哈希。`generated/` 保留五个方案的原始网格、原纸样、诊断、OBJ、回归汇总，以及默认双片裙与裙摆增量 10 cm 的三视图。三视图由实际网格栅格化生成，是诊断渲染，不是 App 截图。

全部方案的收敛标志和质量数值来自各自原始诊断，未通过的输出不会被改为通过。源端点和边／接缝语义对照是二维保真证据；共享接缝残差为零来自拓扑构造。三档面料为未标定的实验数值预设，计算耗时来自 Mac，不代表 iPhone 17 Pro 真机结果。

本报告只进行源文件、JSON、哈希、JavaScript 语法与实际栅格图检查。内置浏览器此前明确拒绝自动打开本地文件 URL，因此本轮未使用其他浏览器或服务绕过限制；交互页面供用户手动打开复核。
