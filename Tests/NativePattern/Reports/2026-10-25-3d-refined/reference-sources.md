# 3D 成衣验证：官方参照与对比边界

检查日期：2026-10-25。此文件记录官方参照来源和复现条件，**不表示本项目已达到官方 3D 仿真效果**。生成结果与实测指标由本目录的后续报告补充。

## 可复现的圆裙输入

现有 `Tests/NativePattern/Fixtures/skirt-circle.json` 来自 GarmentCode 固定提交 `d449629979028123a5c4dc9e732a2ec19b7fce31`，由 `Tests/NativePattern/GenerateOfficialGoldens.py` 生成。该本地 JSON 的 Git blob 为 `a4cc07bac9e3dce6d3414c933b104a5c9aab7163`。

输入为官方 `mean_all.yaml`、默认设计、`meta.bottom=SkirtCircle`，无上装及腰头。官方输入来源：

- [固定版本的人体尺寸](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/bodies/mean_all.yaml)
- [固定版本的默认设计参数](https://github.com/maria-korosteleva/GarmentCode/blob/d449629979028123a5c4dc9e732a2ec19b7fce31/assets/design_params/default.yaml)

由 fixture 原始圆弧解析得到以下数值；这些是网格化前的裁片基准，不是垂坠后投影尺寸：

| 指标 | 官方值 |
| --- | ---: |
| 裁片数／侧缝组数 | 2／2 |
| 展开量 suns | 0.75 |
| 每片展开角 | 2.3561944901923444 rad |
| 腰弧半径 | 17.896188186297707 cm |
| 下摆圆弧半径 | 58.43764818629771 cm |
| 裙长／每条侧缝长 | 40.54146 cm |
| 总腰弧长 | 84.3338 cm |
| 总下摆弧长 | 275.38092935270663 cm |
| 两片总平面面积 | 7291.680155731789 cm² |

该人体身高 171.99 cm、腰围 84.3338 cm、臀围 103.478 cm。fixture 保留官方初始摆片：前／后片平移约为 `[-16.533922,108.7725,+15]` 与 `[-16.533922,108.7725,-15] cm`；接缝为前片边 0 ↔ 后片边 3、前片边 2 ↔ 后片边 1；单位为 `units_in_meter=100`。初始摆片不是最终垂坠结果。

## 已取得的公开效果图

以下原图仅用于项目研究报告对照，不打包为 App 人体、成衣或产品宣传资产。保持原图；如后续裁切、重排，应注明处理方式和原始来源。

| 本地文件 | 官方来源 | 内容与适用范围 |
| --- | --- | --- |
| `references/garmentcode-header.png` | [GarmentCode 仓库示例图](https://github.com/maria-korosteleva/GarmentCode/blob/main/assets/img/header.png) | 官方多款衣服的三维垂坠拼图；可比较整体轮廓、腰部支撑、裙摆褶皱与裁片颜色表达，不能推断其中某件与当前圆裙参数完全一致 |
| `references/design2garmentcode-result-text.png` | [Design2GarmentCode 官网文字生成结果](https://style3d.github.io/design2garmentcode/static/images/result_text.png) | 图 (b) 包含环扇形裙片及连衣裙正背面垂坠；可作圆裙外观的定性参照。左栏为该方法，右栏为其对照方法 DressCode，不能把右栏误标为 Design2GarmentCode |

下载文件校验：

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `garmentcode-header.png` | 605013 | `e3cd112937455057f16e3405d5f6c67380d6622cb2ee4b6d978c1c16d284855c` |
| `design2garmentcode-result-text.png` | 813414 | `3332c598b4901683d1b197a60bd6721946b4b7c8df34f351dca4658c5fc7c787` |

相应 GitHub 图像 blob：GarmentCode `eee6e234ef8fbd3a668dfc0bb84e58cb82e72c2d`；Design2GarmentCode `2c0a5287f0fe3b88f972cb46385b91be0bcd849c`。Design2GarmentCode 官网源仓库默认分支为 `master`，实现代码仓库为另一项目 `design2garmentcode-impl`。

可继续查看的官方视觉来源：

- [GarmentCode 论文网站](https://igl.ethz.ch/projects/garmentcode/)及其[历史服装示例图](https://igl.ethz.ch/projects/garmentcode/teaser.jpg)。
- [GarmentCodeData 网站](https://igl.ethz.ch/projects/GarmentCodeData/)，说明其数据含裁片、人体和三维成衣，适合后续建立同输入基准；本次没有下载完整数据集。
- [Design2GarmentCode 官网](https://style3d.github.io/design2garmentcode/)及其[分层裙参数变化示例](https://style3d.github.io/design2garmentcode/static/images/neural_symbolic-app_new_code.png)。该图说明参数对形态的影响，不是当前圆裙的同输入实验。
- 官网公开视频为 `static/videos/index.mp4`、`sketch.mp4`、`text.mp4`、`picture.mp4`，本次未下载视频或模型权重。

## 在线配置器能否提供精确三维参照

2026-10-25 实际 GET 检查了 [GarmentCode 在线配置器](https://garmentcode.ethz.ch/) 的公开 NiceGUI 页面。网页内帮助说明了以下正式工作流：选定设计 → 进入 3D 视图 → 点击 `Drape current design` 在服务器运行物理仿真 → 点击 `Download Current Garment` 下载当前状态。帮助说明下载 ZIP 含设计、人体、裁片文件，并在已完成三维预览时附带三维模型。

**重要限制：当前在线帮助明确说明，所有三维预览使用默认人体，并不随人体尺寸修改而改变。** 因而通过该网站复现时，应先保持其默认人体；不能把修改人体尺寸后的预览宣称为相应定制人体上的仿真。

初始 HTML 不含当前圆裙的静态 OBJ／GLB 下载地址。三维场景在客户端初始化及用户触发仿真后更新。后续通过浏览器选择了默认圆裙并进入三维视图，尝试触发垂坠；会话反复重载，未能确认任务完成或下载最终网格，未上传用户量体或项目文件。因此，目前**缺少同输入的官方最终三维网格**，还不能报告表面距离或声称与官方数值等价。网页说明提供取得更严格比较数据的正式途径，并非断言官方不提供模型。

## Design2GarmentCode 与 GarmentCode 的关系

[Design2GarmentCode 官方 README](https://github.com/Style3D/design2garmentcode-impl#3-optional-enable-3-d-simulation)要求安装 GarmentCode 的定制 Warp 仿真器；其[三维入口](https://github.com/Style3D/design2garmentcode-impl/blob/main/test_garment_sim.py)调用 `pygarment.meshgen.boxmeshgen.BoxMesh` 和 `pygarment.meshgen.simulation.run_sim`。因此两者不是独立的布料物理后端。

Design2GarmentCode 的公开 `assets/Patterns` 提供 `dress_pencil_specification.json`、`hoody_mean_specification.json`、`js_mean_all_specification.json`、`shirt_mean_specification.json`；未在该目录找到当前圆裙的最终垂坠网格。对比其新增的图文理解／程序生成能力并不属于本轮圆裙物理原型的功能验收。

其[默认仿真配置](https://github.com/Style3D/design2garmentcode-impl/blob/main/assets/Sim_props/default_sim_props.yaml)包含仿真分辨率、材料、三角形／边碰撞、人体碰撞和腰部附件约束。该配置 Git blob 为 `7ee52d245f2f0d06bd9762d72df66b7296255389`。Apple 或本项目求解器的刚度参数不能直接照抄该数值后宣称材质等价；需另做相同尺寸布片的拉伸、弯曲、摩擦标定。

## 对比协议与实际结果

| 层次 | 必须固定的条件 | 可以给出的结论 | 当前记录位置 |
| --- | --- | --- | --- |
| 原始裁片／网格化 | 固定官方提交、人体、设计、单位和接缝 | 轮廓、边长、面积和接缝映射保真 | `comparison.json`：源端点／圆弧半径最大误差 3.55e-15 cm，平面网格面积误差 0.05782%，侧缝流形／方向通过 |
| 自身仿真质量 | 固定人台、网格、初始化、材料、重力、附件约束与停止条件 | 接缝残差、应变、顶点碰撞、稳定性和耗时 | `generated/*-mesh.json` 与 `index.html`，下表为实测 |
| 公开图片外观 | 标注参数／人体／面料／相机差异 | 仅比较轮廓、褶皱、裙摆和明显失败，不能计算三维误差 | `index.html` 的交互网格与两张官方原图，可切换正／背／侧面 |
| 严格三维等价 | 同输入官方最终网格、同人体、校准后的材料、相同坐标及尺度 | 归一前的尺寸误差、表面距离、投影轮廓、碰撞差异 | 未取得同输入最终网格，待补；不得标记通过 |

对比图至少同时给出正面、背面、侧面，注明是实际仿真结果还是初始摆片。允许模型为查看而旋转、平移；计算尺寸误差时不得各自自动缩放以消除真实差异。公开图的未知参数不得用视觉猜测补成精确数值。

本项目实际输出（M5 Mac、优化编译，非 iPhone 性能数据）：

| 圆周倍数／径向裙长 | 顶点 | 计算秒数 | 最大网格边应变 | 持续稳定检查 |
| --- | ---: | ---: | ---: | --- |
| 0.5／40.54146 cm，中等 | 806 | 2.21 | 3.66% | 通过 |
| 0.75／40.54146 cm，中等 | 1040 | 4.40 | 4.42% | 通过 |
| 1.0／40.54146 cm，中等 | 1274 | 8.20 | 7.65% | 通过 |
| 0.75／53.33478 cm，中等 | 1632 | 11.49 | 7.15% | 通过 |
| 0.75／40.54146 cm，柔软 | 1040 | 4.38 | 4.53% | 通过 |
| 0.75／40.54146 cm，挺括 | 1040 | 4.17 | 5.29% | 通过 |

停止检查要求至少连续 24 步最大顶点位移速度小于 0.025 m/s，同时最大网格边应变小于 8%、人体碰撞场的顶点穿入估计小于 3 mm、末态非相邻布片三角面交叉数为 0。标准人体使用 32 次约束迭代，没有放宽阈值。6 份原始网格及诊断已复制到 `generated/`，`run-cloth-refined.sh` 同次验证原圆台基线，顶点位置与旧版最大差为 0。柔软、挺括相对中等面料的实际顶点 RMS 差分别为 15.88 mm、17.01 mm。共享接缝间隙为 0 是共享自由度的构造性质，不是对照官方最终网格得到的精度。

本版使用具有腰腹臀腿轮廓的标准人体：官方 MakeHuman 固定提交 `a8bc2d54ff0ac92e78ff71431b1023eda42bf482` 的 CC0 `base.obj`，只保留 body 组并按参考尺寸归一；来源、哈希和许可见 App 的 `GarmentCodeStandardBodySource.json`、`MakeHuman-CC0-LICENSE.txt` 与根目录 `THIRD_PARTY_NOTICES.md`。它按尺寸有限拟合，不是个人身体重建。可见人体与 1 cm 距离场同源，场覆盖脚底至腰线上方 20 cm；实际腰口轮廓的网格／场最大偏差约 0.920 mm，上半身尚无完整碰撞覆盖。

布料质量按参考三角面积与单位面积质量计算，接缝质量守恒；柔软／中等／挺括分别为 120／180／280 g/m² 的数值预设。弯曲仍为二阶距离近似，没有跨接缝弯曲约束。表面接触包含顶点与三角面、边与边、面内穿插修正及末态交叉检查，已修复旧整圆裙一处顶点碰撞漏检的跨缝穿插；它不是连续碰撞保证。未进行样布实物标定，也未完整检查所有布片三角面与人体的相交。

默认三视图见 `generated/circle-0.75-views.png`，从实际网格栅格化得到，不是 App 截图。当前已改善人体轮廓和离散自碰撞，但依然缺同输入官方最终网格与面料标定，**不能据此标记为与 GarmentCode／Design2GarmentCode 同等质量**。

集成验证：Release 的 iOS 设备目标与 arm64 模拟器目标均构建通过，使用本机 SwiftUI 编译插件时以命令行 `OTHER_SWIFT_FLAGS=-disable-sandbox` 规避执行环境对编译插件的限制，未修改项目持久构建设置。人体、表面接触、面料质量专项和 7 项真实求解集成均通过；没有把本轮结果冒充重新运行完整 356 项二维验收。Device Hub 的 iPhone 17／iOS 27 模拟器已实际生成标准人体上的中等、柔软材料，两者均收敛、末态布片交叉数为 0，耗时分别为 4.3、4.4 秒。面料切换会清空旧网格、更新克重并要求重新计算，人体首次显示完整且自动适配视野；截图见 `generated/app-simulator-soft.png`。这些不是 iPhone 17 Pro 真机性能数据。

报告检查：JavaScript 语法、全部数据与校验值、二维对照记录及独立实际网格三视图均已检查。自动打开新版 HTML 被内置浏览器的本地文件 URL 安全策略拒绝，因此未进行新版报告的浏览器交互复核；可由用户手动打开文件查看，未改用其他浏览器或服务绕过限制。

## 归属与许可

GarmentCode 示例归 Maria Korosteleva 等原作者，仓库采用 [MIT](https://github.com/maria-korosteleva/GarmentCode/blob/main/LICENSE)，本项目保留的许可见根目录 `THIRD_PARTY_NOTICES.md`。Design2GarmentCode 示例归 Feng Zhou、Ruiyang Liu、Chen Liu、Gaofeng He、Yong-Lu Li、Xiaogang Jin、Huamin Wang，官网页脚标注 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)；此处提供来源归属，保持原始图片。

人体素材需逐项核对[官方说明](https://github.com/maria-korosteleva/GarmentCode/blob/main/assets/bodies/Readme.md)与来源许可，不能由代码许可推定人体可直接用于商业 App。GarmentCode 定制 Warp 的[许可](https://github.com/maria-korosteleva/NvidiaWarp-GarmentCode/blob/main/LICENSE.md)限制为研究／评估用途；本次只查阅来源，未引入该代码为产品依赖。
