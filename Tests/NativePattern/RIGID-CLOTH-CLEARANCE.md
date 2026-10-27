# 显式人体与布片刚体间隙初始化

`GarmentCodeNativeAssembly.Initialization.rigidBodyAndClothClearance` 是新增的显式选项。`nativeConstruction`、`rigidBodyClearance` 以及默认选择均保持不变。这个选项只初始化独立纸样片：保留平面内原长、源质量、三角拓扑、全部自由度、真实源接缝与零人工固定点，不运行动态仿真，不代表已经缝合、合体或形成成衣。

## 为什么需要布片间检查

原 `rigidBodyClearance` 对完整 211 例的独立人体检查均为 0 穿越、0 内部顶点 / 面心、0 歧义，但其中 14 例仍有布片交叉：

- 默认人体的 9 个 Pants 组合，各有 29 个后裤片正面积共面三角对；独立测量的实体平面重叠约 0.2294 cm²。
- 两个人体的 `Shirt|None|SkirtManyPanels` 分别有 4 / 8 个相邻裙片 proper 穿越三角对。
- 三个裤口代表分别有 17 / 81 / 125 个共面三角对。CuffSkirt 左右前 / 后裙裤口各重叠约 19.2773 cm²，CuffBandSkirt 各约 39.8330 cm²。

这些是三角对数量，不是独立事故数量，也不是近接触或零面积边触。人体清除沿法向移动，不改变同面片之间原有的平面内重叠，因此不能单靠人体 proof 宣称布片无交叉。

## 全三角支持平面算法

新独立模块为 `GarmentCodeRigidClothClearance`。输入必须是完整的前一人体清除结果与每片真实三角索引；验证 panel 集合、既定坐标轴 / outward 符号、源 UV 边界、最终人体支撑平面、有限坐标、索引及非退化面，不接受遗漏的片或三角面。

每步只从目前实际存在 proper / 正面积共面交叉的片中选择。对每个候选片：

1. 保留人体 proof 的同一 `u,v,n` 与固定 outward 符号，不重新选向内方向。
2. 将它的完整 UV 矩形按自身边界误差、其它片的最大边界误差、5 mm 布片壳厚及 1 nm 数值余量扩张。
3. 检查**全部其它布片的全部三角面**。以三个顶点的投影 AABB 选取保守集合，包括投影退化面与 AABB 假阳性；不能按三角中心、原碰撞 pair 或局部邻片过滤。
4. 取集合内所有顶点沿 `n` 的最外支持值，并计入其它片源边界误差与自身微小平面偏差，求沿既定 outward 符号的最小非负位移，使新平面超过全部支持值至少 5 mm。
5. 在当前冲突候选中选择所需位移最小者，整片平移，重新检查真实交叉。任何新 pair、未消失的被移动片交叉或不严格减少的坏 panel-pair 集合都明确失败。

完整支持候选、panel / local triangle 引用、UV 框、支持极值、方向、位移与每步实际交叉检查保存在独立 cloth proof。原 body proof 保留为前一阶段证明，两者以相同可见人体 SHA 关联。

## 有限步数与人体安全性

移动片的新平面位于所有候选三角的同一外侧；投影在保守框外的三角不能进入它的真实片域。因此该步后所有涉及它的交叉都消失。其它 pair 没有移动，状态不变。下次移动另一片时同样检查全部其它片，包含已经清除的片，不会重新引入已消除的 pair。每步至少让一个冲突片永久退出，最多 `N−1` 次移动。

额外位移与人体 proof 的 outward 方向相同，UV 投影不变，原人体支撑间隙单调增大。最终仍用独立人体三角穿越与三轴闭体 parity 检查，不用 SDF 查询替代它们。

单片额外位移固定不超过 5 cm，累计不超过 15 cm；候选支持测试与三角对测试各不超过 1024 万次，完整冲突记录最多 15 万对。源网格上限 128 片 / 20000 顶点 / 40000 面。调用者只能收紧上限，不能放宽固定硬上限。预算不足、取消或最终几何不清零均明确失败；不会把片移到远处以冒充物理成功。

## 最终位置重建接缝

新选项在 `GarmentCodeAssemblyBuilder.prepare` **之前**执行。Builder 根据最后位置重新构建完整 plan，包含每个实际附着点的 `initialGapMeters` 与 `initialDirection`，以及原 ordinary / right_wrong 方向和明确的源接口意图。不会复用人体清除前的旧 plan。

`GarmentCodeSourceTethers.prepare(input:)` 随后可直接从同一原纸样、最后 plan 与源原长构图。原生输入没有人工 pins，图明确报告不可达顶点 / 组件；不会为了产生 tethers 自动加固定点。

## 永久测试

```sh
sh Tests/NativePattern/run-rigid-cloth-clearance.sh
sh Tests/NativePattern/run-native-rigid-cloth.sh
```

解析回归包含：三片同面片（第二片必须考虑已经移开的第一片，分别移动 5 / 10 mm）、三个不同法向、三角中心在 UV 框外但真实 AABB 相交、两侧源边界误差、已清零位置逐值不变，及 15 个错误输入 / 资源与位移硬预算 / 开始和中途取消拒绝场景。使用独立 Moller–Trumbore 与共面凸裁剪 oracle 检查结果，不套接缝豁免。

完整 211 例统一验证：

- 新选项 211 / 211 通过独立人体 proper、内部 / 歧义顶点及面心、布片 proper 与正面积共面检查，计数全部为 0。
- 原 197 个已清零案例的完整数值状态和 plan 与 body-only 模式相同，未移动。
- 14 个真实冲突案例修复；最大单片额外位移约 33.518 mm，最大累计约 73.695 mm，没有扩大预算。
- 两个旧选项各 211 例，合计 422 个完整状态签名，与改动前实际捕获的永久 goldens 全部一致。签名覆盖 world / reference / 可见人体坐标、所有面 / DOF / pin、质量和源弹簧原长、所有 mesh、完整 plan。
- 最后位置的实际 `initialGap` 与 `initialDirection` 误差均为 0，211 个新源 / plan 的 tether 图全部正常构建，质量和零人工 pins 保留，最大源应变约 `1.739e-13`。

原双选项 goldens 为 `Fixtures/native-initialization-old-mode-goldens.json`，保存捕获前完整源与资源 SHA 清单。`NativeInitializationState.swift` 定义精确值签名，`NativeRigidClothChecks.swift` 执行旧选项与新模式的全检查。来源改变时不能用当前结果直接覆盖旧 goldens，以免隐藏默认行为变化。

## 仍未证明的事情

这些检查只证明采样网格没有实际 proper / 正面积共面交叉；全矩阵仍有最多 792 个生产接触检查器报告的近接触 pair，不能称为“无接触”。源构造时的大接缝间距仍然存在，尚未闭合。真实衣服需要下一阶段的联合缝合、布料能量、人体 / 布片碰撞与 CCD、悬垂和严格物理验收；本选项不宣称成衣通过或实机性能。
