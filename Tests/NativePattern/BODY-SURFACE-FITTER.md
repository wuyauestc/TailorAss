# 四类表面尺寸的可选拟合草案

`GarmentCodeBodySurfaceFitter` 是独立、显式调用的草案拟合器。默认 StandardBody、旧摆臂、旧 SDF、固定碰撞人体和当前布料运行都没有调用它。它返回可检查的真实网格、残差和失败状态；当前不发放人体碰撞凭证。

量法和原面数据见 [人体表面参考量法](BODY-SURFACE-MEASUREMENTS.md)。目标只有四种：`bust`、`shoulder_w`、`arm_length`、`wrist`；实际残差有六项，因为左右臂和左右腕分别重测。肩部使用横向宽，另一个三维肩点跨度只保留作参考。没有移动测量点、替换表面路径或改写输入来匹配目标，也没有宣称其他26项人体参数分别拟合。

## API 和来源

```swift
let fitter = try GarmentCodeBodySurfaceFitter.Prepared(
    contractData: contractData, templateData: templateData, rigData: rigData,
    auxiliaryWeightsData: auxiliaryWeightsData)
let attempt = fitter.fit(source: canonicalSnapshot,
    bodyValues: body.values, isCancelled: { cancellationRequested() })
```

`Prepared` 绑定固定量法资源、原 CC0 模板和原 rig 的完整 SHA。输入为生产 `GarmentCodeStandardBody.load` 创建的不可变 `Snapshot`，拟合前还逐位重放原五尺度变形，核对完整33参数与真实原坐标。摆臂后的网格或其他参数生成的快照不能冒充原参考姿态。

`Attempt` 保留源几何/参数 SHA、契约/rig SHA、原三角面编号、真实草案顶点、六项残差、四控制量、每次已提交迭代的实际代价、评估次数、面质量和重新测量报告。`diagnosticMeasurement` 中的 `bodyFittingApplied=false` 描述只读测量器本身；拟合草案的实际变形由外层 `Attempt.diagnosticPositions`、控制量和状态记录。

达到目标时状态为 `draftSurfaceGoalsReached`。每个 Attempt 明确包含 `requiresCompleteIntersectionAudit=true`、`bodyCapabilityIssued=false`、`compatibleWithLegacyInverseSDF=false`。需要完整自交审计和后续新的拟合人体凭证，才可交给显示/碰撞/摆臂链；现有 `FixedSurfaceReceipt` 的原五尺度重放和旧 inverse SDF 不适用于这个草案。

## 变形和求解

四个控制量及有限域如下。肩控制量在向量中按 `translationMeters / 0.05` 保存。

| 控制 | 变形 | 有限域 |
| --- | --- | --- |
| 胸部 log 径向缩放 | 固定躯干权重与参考高度窗内的 x/z 连续缩放 | 实际倍率 0.75…1.3 |
| 肩横移 | 两侧原 CC0 上肢权重混合的反向 x 位移 | ±0.07m |
| 上肢 log 长度缩放 | 以当前肩表面附着为枢轴，按原局部权重缩放 | 实际倍率 0.65…1.2 |
| 腕部 log 径向缩放 | 原参考腕平面窗口内，绕当前表面腕中心/前臂轴缩放径向分量 | 实际倍率 0.7…1.4 |

变形数学只由 [FitDeformationReplay](FIT-DEFORMATION-REPLAY.md) 实现；拟合器持有其 `Context`，每次目标评估调用 `context.deform`，已经移除自己的 mask、腕平面 SVD/Jacobi 和变形实现。权重只定义局部变形场，不用骨长来当测量。可见13380点与原1117个辅助源点共同经过同一场，135个重合源点逐位一致，326个 rest 骨代理由拟合后的辅助点求原引用均值。

所有共享顶点只变换一次，固定原面插值因此保持相邻面的 C0 连续。零权重采用 `expm1` 的零位移形式，局部外顶点逐位不变。计算顺序固定为胸/肩、左臂、右臂、左腕、右腕；每段的中心/轴从当时实际可见表面重新计算。腕参考法向由原腕环协方差的最小特征向量确定，使用固定32轮以内的3×3 Jacobi 求解。

求解采用4维有界 LM、中央有限差分和真实固定表面残差。只有实际代价降低才提交迭代；候选含非有限、退化或相对原法线反向的面时拒绝。默认最多24迭代、512实际目标评估，最多12次阻尼尝试/迭代；所有次数都有硬上界。32MiB 是保守临时工作区预留，指本模块新增工作区，不是整个 App 进程 RSS 上限。

默认目标绝对容差为 `1e-5m`。预算、不可达有限域、无进展、错误来源、错误选项与取消都有明确状态，并保留最后一次真实有效残差；尚未开始测量就取消时残差为空，不能补造。提交改进后的取消和最终发布时的取消都不会返回目标已达状态。

入口、取消回调后和发布前要求 nearest 舍入环境。首次回调改变舍入模式会被锁存，之后不会再调用用户回调来掩盖该错误；失败保留先前缓存的有效残差，不在错误舍入环境下重算它。iOS 必须有 Native 的 C FPU 桥，缺桥时明确拒绝。本模块不修复或修改调用者的浮点环境。

## 实际结果与检查

已在默认、女性两份生产加载的原人体上运行。两者都用3次提交迭代、28次实际目标评估同时达到六项表面目标；最大残差分别为 `2.342e-9m`、`5.133e-9m`。原网格最大误差原为约7.970cm和8.070cm。此结果只覆盖两份真实输入与这些项目量法，尚未建立任意人体域的拟合保证。

独立 NumPy 实现使用相同源、固定路径和 Swift 最终控制量重新变形，没有重新优化或替换输出。逐顶点最大差小于 `1.15e-16m`。所有原13380顶点/26756面、完整33参数与原表面附着保留；局部外7975/7967顶点逐位不变。两侧同参数场的最大镜像差约0.033/0.035mm，如实保留原权重与执行顺序造成的微小不对称。

长期专项对实际 Swift 最终网格另做完整静态三角面审计：inclusive AABB 覆盖全部候选，Fraction 检查真实二进坐标的闭三角形相交，包括共享顶点/边；只把真实共享 simplex 上的接触判为合法。两份实际结果分别有177324/176981候选，均无真实交叉、未知或退化，40134条闭合有向边保留。该专项证明最终两网格，没有颁发整段形变的扫掠证书。

```sh
python3 Tests/NativePattern/run-body-surface-fitter.py \
  --package-proof /path/to/sealed-native-proof
```

使用含 NumPy 的 Python；可通过 `--python-packages` 指定匹配版本的依赖目录。Runner 冻结全部12个生产模型、driver、独立 oracle 和实际资源，检查 before/copy/after 字节绑定；执行 Mac 严格编译、真实人体和否定/预算/取消/RNE/并发控制，以及两份完整独立静态几何审计。

SDK 验证真实链接 iOS17 arm64 和 Simulator17 x86_64 二进制，当前安装 SDK 为27.0；本次交付另外检查了实际 Mach-O 平台/架构。为避免依赖未记录的旧 `.swiftmodule`，从 sealed Native129 全部9份 Swift 源重新发出接口，链接其原有 SDK `.a` 与 C FPU 桥；675份冻结输入、全部546份 Sources、原 archive SHA、新接口 SHA、C modulemaps/头文件均绑定。没有重编 C++、重跑 Native129 套件、安装或运行这些 SDK 二进制。

首次独立模块的7条命令保留为历史证据；当前共享 Replay 版本9条实际命令全部终态0，可见点、控制量和几何 SHA 与独立版本完全相同。共享 Replay 的两人体30°/45°/60°六个实际 posed 表面也完成全三角 Fraction 静态相交审计，均无真实交叉、未知或退化；这仍不是扫掠姿态证书或完整人体碰撞凭证。旧 Rig/FixedSurfaceReceipt/SDF 没有被替换为拟合路径，默认布料运行没有使用这些草案。
