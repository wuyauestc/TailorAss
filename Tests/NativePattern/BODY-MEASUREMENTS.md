# 同源人体参考测量

`GarmentCodeBodyMeasurements` 是独立的几何测量模块，不变形人体、不改变旧 StandardBody／Rig／SDF／回执，不接 App 路由，也不执行布料求解。它将实际可见网格与当前26项原始、7项派生值绑定，回答“声明平面的哪一个闭环包含声明轴点、其周长是多少”。

## API 与来源

```swift
let prepared = try GarmentCodeBodyMeasurements.Prepared(
    positions: actualVisiblePositions,
    triangleIndices: actualVisibleTriangleIndices,
    bodyValues: originalBody.values,
    isCancelled: { token.cancelled })
let report = try prepared.referenceReport(isCancelled: { token.cancelled })
```

`Prepared` 只能通过实际数组构造；内部 Snapshot 构造受限，没有接受外部声称的 geometrySHA 或 `isValidated` 标志。原始数组只读保留，使用既有 `BodySections.slice` 完成闭合、方向、顶点扇和组件体积检查并取得同一 `rigid-clearance-visible-body-v1` SHA。这个拓扑检查不是全人体无任意自交证明，也不是个人体型资格证。

Snapshot 同时保存完整位置、面索引、33个实际参数和独立 `parameterSHA256`。后者按有版本前缀、排序键、原 Double 位模式编码；修改未被人台使用的 underbust 仍会改变参数SHA，不会谎称网格因此拟合。模块核对全部7项派生值，并要求本模块实际比较的height/bust/waist/hips目标为正；这不等于给全部26项发明人体范围。测试包含每项−1与0、派生仍由真实BodyParameters重算的8个非正子例。模块不补默认，不丢未知键；当前版本不接受超出这33键的扩展。这个 Snapshot 只是测量来源，不替代任何旧 FixedSurfaceReceipt 或 Rig.ValidatedBody。

`Report.height` 是实际全部顶点的 `maxY−minY`，目标比较是原输入height。它明确叫可见网格竖直范围，没有另行检测头顶、赤足点或姿态。

## 三个默认参考面

| 测量 | 平面（米，当前腰原点坐标系） | 比较目标 |
| --- | --- | --- |
| waist-reference | y=0 | 原 waist / 100 |
| hips-reference | y=−hips_line/100 | 原 hips / 100 |
| chest-vertical-reference | y=(waist_line−vert_bust_line)/100 | 原 bust / 100 |

声明轴是经过(0,0,0)、方向+Y的参考直线。胸部采用原垂直胸高，**不使用**混合贴体胸高的 `_bust_line`。它是构造参考面，不是自动找到最丰满胸围平面。

每项包含原请求的轴、平面、公式、目标键，全部原 `BodySections.Section`（所有环、每个交点的原边ID和插值、每段原三角面ID）、轴面交点、选中环序号、实际周长和 `observedMinusRequestedMeters`。后者只叫“参考截面周长减原输入”，不是未经标定的解剖拟合误差。

## 严格选择与未支持状态

轴面交点采用基本算术向外区间；闭环投影去掉平面法向绝对值最大的轴。对返回的离散交线，用向外区间方向谓词与绕数选取**唯一严格包含轴点**的环。8个有限的线性投影方向仅用于处理射线经过顶点的数值歧义，不移动平面、交点或任何源顶点。不存在“最大环”“环周长求和”或凸包替代。

选择的严格性针对既有 BodySections 返回的数值离散轮廓；切片本身继续沿用其声明的平面误差带与 indeterminate 规则，没有新增通用精确三角面求交区间证明。独立实际测试另以原始Float64三角面的精确Fraction截面复核选择。

- 原截面 indeterminate：`sectionIndeterminate`，不平移平面再试。
- 轴与平面平行或无法确认非平行：`axisParallelOrUncertain`。
- 轴点落边／角／声明数值带：`anchorOnBoundaryOrUncertain`。
- 无闭环包含轴点或多个包含：`noContainingLoop`／`multipleContainingLoops`；嵌套壳不自动选外圈。
- 算术或有限射线方向仍不明：`numericalSelectionUncertain`，不猜测。

以上情形保留完整Section，几何状态为unsupported，没有选中环或部分周长。合法几何选择的状态是 `measuredReference`。

**所有结果另有 `anatomicalComparisonStatus=unsupported`、`anatomicalComparisonIssue=uncertifiedAnatomicalRegion`。** 唯一包含轴点不证明该环已排除连接的肩臂，不证明自然腰／臀峰／胸部最丰满处，也不证明该33项已驱动人体。实际y=0.30m探针只产生一个很宽的上身环，模块可报告这个参考周长，但仍不给胸围解剖资格。

## 预算、取消与浮点环境

默认最多8个请求，硬上限16；选择边测试在整份报告内累计，默认100万、可设1～800万。每项截面沿用有界BodySections预算。记录实际边测试及射线方向次数，不把数值预算当内存RSS报告。超限抛错，不返回前几项的部分Report。准备、截面、选择循环和发布前均检查取消；取消抛 `CancellationError`，不发布部分结果。

区间选择仅在nearest rounding环境工作，不改变线程舍入模式；Mac用只读Darwin检测，iOS使用已有NativeClothCollision浮点C桥。没有该桥的平台明确拒绝。旧内核及包没有因此修改。

## 真实结果与验证

运行：

```sh
python3 Tests/NativePattern/run-body-measurements.py
```

runner冻结所需实际模型、资产、女性输入和独立检查器，以Swift5／默认MainActor／严格并发／warnings-as-errors进行Release编译。不编译C++，不装App。

解析控制包含方盒周长、不同大小的多个闭环（选择较小的含轴环而不是最大环）、平移坐标与轴、斜面矩形；负控包含边／角／边外1ULP、空截面、源顶点面、平行轴、嵌套多包含、缺／篡改参数、坏源、有限预算、取消和非nearest舍入。并行只读调用保持同一编码输出。不会用“几何唯一包含”冒充解剖测试。

默认与官方女性输入来自当前实际StandardBody，三项周长如下；每项完整环均保留：

| 输入profile | 腰参考/cm | 臀参考/cm | 胸垂直参考/cm | 环数（腰/臀/胸） |
| --- | ---: | ---: | ---: | --- |
| default | 84.309031 | 103.540457 | 103.880708 | 3 / 1 / 3 |
| female | 80.329087 | 104.139094 | 98.707694 | 3 / 1 / 3 |

胸参考周长比原bust输入分别大约40.4001mm、13.0009mm；这些差值仅说明本声明参考面的比较结果，不是已确证的真实胸围误差。两个profile仍是同一CC0模板的现有有限变形，不是两份独立人体扫描。

`ValidateBodyMeasurements.py` 独立从全部实际三角面重新水平切片，以原边图追踪所有闭环，用 `math.fsum` 重算周长，并以原始Float64值的精确Fraction交点和绕数确认唯一包含。另独立复核几何／参数SHA、所有源边／三角面来源、选中序号和残差。它不链接Swift实现，也不读取AGPL量体路径数据。

首轮严格编译成功，但测试误将女性fixture的parameters.body当顶层body读取，运行失败；原结果保留。修正后的中间通过证据分别保留。最终严格编译、聚焦控制和独立6截面oracle在 `/private/tmp/TailorAssBodyMeasurementsComplete`，最终iOS17 arm64真实浮点桥API分支严格typecheck在 `/private/tmp/TailorAssBodyMeasurementsIOSComplete`，均命令终态0且输入未变。统一索引 `/private/tmp/TailorAssBodyMeasurementsDelivery/delivery-manifest.json` 绑定最终模型、测试、文档、实际JSON、二进制与原失败；没有重编原生包或宣称iOS运行。本功能没有拟合26项尺寸，也没有重跑或宣称完整成衣通过。
