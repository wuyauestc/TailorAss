# 同一牛顿点的精确弹性 Hessian 缓存

`GarmentCodeElasticLinearization` 只计算固定实际坐标 `x` 的矩阵自由 raw
Hessian 方向积。不增加能量、针脚、质量、投影、阻尼或求解器，不改变原始
Membrane/Hinge 的 E、g、材料、源度量和可行域。

```swift
let source = try GarmentCodeElasticLinearization.Source(
    membrane: preparedMembrane, bending: preparedHinges)
// Source 在整个求解过程中只准备一次。
let linearization = try GarmentCodeElasticLinearization.Prepared(
    source: source, positions: actualNewtonPositions,
    material: membraneMaterial, barrier: principalStrainBarrier,
    bendingMaterial: experimentalBendingMaterial)
let elasticHv = try linearization.hessianProduct(direction: direction)
```

每个新的牛顿点需要新 `Prepared`，同一点的所有 CG 方向复用它。输出按原顺序
`(NH + principal barrier) + hinge` 相加。三个分量也分别可调用，便于独立对照。
没有把 raw Hessian 换成 PSD/Gauss–Newton 或把方向相关量冻结。

`Source.identity` 是不进入 canonical JSON 的运行期 UUID：复制 Source 保留
identity，重新构造得到新值。宿主接入缓存时仍须核对 Source identity、实际 x
逐值一致，以及 mu/lambda、所有 barrier 字段、kb 一致，防止另一个源、另一个
位置或材料的 stale cache。Source 使用已有 `ElasticEnergyDelta.Prepared`
相同的完整内部边、面方向、源面积及源边长校验；canonical SHA 证明仍由调用者
的真实来源准备器提供。`positions` 为只读 CoW 快照，外部修改原数组不修改缓存。

## 缓存的数学量

NH 取 `F=[u v]`、`C=FᵀF`、`M=C⁻¹`、`J=|u×v|`，缓存 `F`、`M`、
`F M=[hu hv]` 和 `β=λ log J−μ`。每个方向仍重新计算 `δF`、`δC`、
`δM=−M δC M`、`δlogJ=hu·δu+hv·δv`，代回原始 `δP`，再以原 `du/dv/A0`
散射到原 source IDs。

主伸长 barrier 缓存同一点的两个主伸长、特征基，以及原 scalar barrier 的一、
二阶系数和 divided difference。严格未激活时一、二阶均为零，其 Hessian 才
确实为零；域外仍拒绝。重复主伸长继续采用原解析极限，没有相减或 epsilon
近似。即使全局未激活，也完整校验方向的数量、finite 与取消。

内部 hinge 仍为 `E=kb*w*θ²`，精确方向积为
`2*kb*w*(q*(q·p)+θ*Dq[p])`。缓存 `θ/q/e/v/w/L/n1/n2/a/b`；`Dq[p]` 每次
按原公式计算，不丢掉 `θ*Dq`。仅原 source 内部边参与，没有跨未缝接口的假铰链。
`kb==0` 明确跳过整个当前 hinge 组件，与原 joint objective 的 disabled 分支一致。
非零 kb 在构建时调用一次原 Hinge.evaluate，以尊重其私有、自定义退化与 π 分支
域，再构建缓存；这次额外验证计入构建时间。没有猜默认域来放行严格 Prepared，
也不因默认域更大而误拒另一份合法自定义 Prepared。

## 边界与回归

源预算沿用已有 20k V、40k T、60k hinge；新增缓存估计默认上限64MiB，可配置
到256MiB，在分配状态数组前检查。估计含数组容量与 CoW 驻留的保守余量，
不是系统 RSS 测量。真实2000V/3472T/4948hinge非零弯曲控制的上界为4220864B。
每阶段和每128元素检查取消，错误不返回部分方向积。

运行 `Tests/NativePattern/run-elastic-linearization.sh`。长期 fixture 保留原始
236与237数学状态字节，canonical paper SHA
`28eb56b2ec46feddde570c300896cd6422045e6d119d0a2af11f667ae7604a35`；
237 raw SHA `2deee444e5a1279167cd4277c4e72229797d68986a067290ba7f04a77cb9ef43`。
237仅是数学平衡状态，不是新物理步骤或成衣验收。

专项包括真实236/237与明确标记为派生测试的 `237×1.04`（全部3472面 barrier
激活），每态10个方向逐个 Double.bitPattern 对照三个原始分量及按原序总和；
实际236→237位移方向、原始 gradient 的FD步长扫、重复主伸长、刚体协变、
自定义 Hinge π 域、kb0跳过、Source identity/CoW、8并发只读、错误方向/NaN、
缓存预算、错源和开始/中途取消。实际态非零弯曲值2e−4 N·m只用于导数控制，
没有实物标定，也不更改三档面料预设。

纯微基准不能代表整体 App 或物理步骤速度。宿主仍需真实 Newton/KKT、完整
source/body/self 路径限制和最终几何验收；缓存不提供新的收敛证明。
