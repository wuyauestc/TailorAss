# 稳定的弹性能量差值

`GarmentCodeElasticEnergyDelta` 计算固定源数据和两个实际 Double 坐标端点之间的 **NH + 主伸长屏障 + hinge 弯曲能量差估计**。它没有接入旧求解器、App 路由或面料预设，不推进物理，不修改源长度、面积、质量、接缝或 pins。

## 接口与使用边界

```swift
let delta = try GarmentCodeElasticEnergyDelta.Prepared(
    membrane: membranePrepared, bending: hingePrepared)
let estimate = try delta.evaluate(
    from: currentPositions, to: actualRoundedCandidate,
    material: membraneMaterial, barrier: strainBarrier,
    bendingMaterial: bendingMaterial)
```

只计算膜能量时可省略 `bending` 和 `bendingMaterial`；两者必须同时存在或同时省略。`barrier` 可省略，但提供时会计算两种主伸长的全部上下激活分支，不能以“多数未激活”代替该项。

数据必须来自调用者同一份已验证源 `PreparedInput`。本模块再核对 membrane/hinge 顶点数、完整内部边、源面方向、邻面面积与源边长度，但不独立认证 canonical SHA。原始 source `du/dv/A0` 和 hinge 权重保持不变。源拓扑核对只在准备时进行，随后重复评估候选。

**`to` 必须是实际舍入后的候选坐标**，不能传入理想的 `alpha * direction` 来代替实际位移。返回值提供 NH、屏障、hinge 和总差值，全部明确为 Double 数值估计；这与现有 E/g/Hv 的数值近似等级一致，**没有普遍符号保证，也没有在线认证误差区间**。后续消费者仍需自己的下降方向、KKT、线搜索和最终几何验收。

## 所计算的同一能量

固定材料系数和源数据后，目标是现有模块定义的解析 NH、主伸长屏障和 Discrete Shells hinge 能量。不是两个已经舍入的 Double 总量的位差。NH 近 J=1 的实现级多项式近似不被重新定义成另一个物理目标。没有增加能量接受容差，也没有以普通总量相减作为失败回退。

- **NH：** 用叉积增量求 `dlogJ = log1p((2N·dN+|dN|²)/|N|²)/2`，配合 `dtrace`，保留 `lambda*logJ0*dlogJ` 和二阶 `lambda*dlogJ²/2`。
- **屏障：** 从 `C=FᵀF` 的 trace/discriminant 增量得到 `dlambda`，再用 `dsigma=dlambda/(sigma1+sigma0)`。重复特征值有独立分支，不除以零谱隙。只有在屏障合法、远离坍塌的谱区间内使用两根 `sqrt((trace±disc)/2)`；没有更改通用 `inspect` 的近坍塌 `J/high` 方法。
- **激活标量：** 上下两边分别令 `x=max(sigma-activation,0)` 或 `x=max(activation-sigma,0)`。对 `B=-k*x²*log1p(-x/w)`，使用 `dB=-k[(2x*dx+dx²)*log1p(-x/w)+(x+dx)²*log1p(-dx/(w-x))]`。跨入、跨出、两端同时激活均保留。靠近严格界限的大相对变化用正剩余量比的 log，避免 `1-dx/r` 被舍入成零。
- **hinge：** 用未归一化的 `S=e·(N1×N2)/|e|`、`C=N1·N2` 及叉积增量求 `dS/dC`，再以 `atan2(dS*C-dC*S,C²+S²+C*dC+S*dS)` 求有符号角增量。能量差为 `kb*w*(2theta0*dtheta+dtheta²)`，原 `kb` 单位 N·m、无额外 `1/2`。

逐元素和逐组件使用 Neumaier 求和，减少相消造成的额外求和误差；它不消除基态 F、谱或角度本身的舍入误差。

## 明确失败与精度限制

严格检查两端的膜面积、主伸长界限、有限米制坐标、hinge 退化、原 ±π 排除带和跨分支。违反时抛错，不修复参数、不截断力或能量。取消传播 `CancellationError`。源准备/评估保留 20,000 顶点、40,000 面、60,000 hinge 的硬预算，可由调用者收紧。

只有极小非零位移导致平方项明显处于下溢范围时，返回 `precisionUnresolved`。还保留基于中间运算绝对量和的严重消减告警：`|delta| <= 32*ulpOfOne*arithmeticScale` 时停止。这是保守的数值停机条件，**不是认证误差界，也不是能量接受宽限**；它不能检测所有近静止的错误符号。

研究中的两个错误总符号压力点，其 100 位 `g∞` 约为 `5e-14 N`，已经远低于当前消费者 `1e-6 N` 的 KKT 停止范围。回归保留一个该类冻结压力点，明确要求停机；不据此声称生产需要或已有任意精度运算。分量下溢或重复谱也不能自动等同于总目标的 Armijo 决策错误。

屏障逼近严格界限时条件数很大，稳定差值公式不保证任意相对精度。消费者不能删掉已激活项、跳过真实梯度/KKT，或在错误后改用普通总 E 相减。源弯曲模型仍有网格方向依赖，`kb` 未标定，见 `HINGE-BENDING.md`。

## 永久回归与证据来源

运行：

```sh
Tests/NativePattern/run-elastic-energy-delta.sh
```

可设置 `GARMENTCODE_ELASTIC_DELTA_OUTPUT` 和 `GARMENTCODE_ELASTIC_DELTA_KEEP_SNAPSHOT=1`。runner 先一次性冻结全部编译依赖，验证 fixture SHA，解压固定控制数据，再以严格并发及 warnings-as-errors 编译。日常回归只需要仓库 fixture 和 Python 标准库，不依赖原研究临时目录、NumPy 或高精度运行时。

`Fixtures/3d-elastic-delta/controls.json.gz` 的生成器只用于归档已有独立研究证据。数据按实际 Double 逐值保存，引用同一 `3d-hinge` canonical 源 `28eb56…a35`、3472 个源面和 4948 个 hinge。所有源 `du/dv/A0` 与 hinge 长度、面积、权重均逐值检查；不复用旧 cone 的不同编号计划。

控制样例包括：

- 原始 κ=0、屏障未激活的 **25 个真实 captured Newton line 候选**。测试将稳定弹性差值与稳定 inertia/sewing 项组合，严格对比 Decimal100 的完整 Φ Armijo 决策，不在阈值上加 epsilon。这些点在独立研究中都有 80/100 位直接端点对照；预步 `g∞=4.4053e-6 N`。只有 19 个舍入后实际 work 为负，极小 alpha 可能改变实际位移方向，不能以理想 `alpha*g·p` 冒充实际 work。
- **4 个完整真实源的激活屏障 + 非零 hinge 样例**：全 upper、全 lower、上下同时、near upper limit；每例 6944 个主伸长项已激活，并核对实际梯度 work 为负。这些是解析应变松弛端点，不是新仿真或该扩展目标的 captured Newton 方向。
- 解析静止/激活切换/重复谱、源不一致、非法域、π 跨支、明确未可判定、预算及取消。

测试中对参考值的浮点精度比较只是回归质量检查，和消费者严格 Armijo 判定分开。独立研究用 Decimal.from_float 精确导入全部 Double 坐标及系数，以 80/100 位直接端点能量作 oracle；这台 Mac 的 longdouble 只有 53 位，没有伪称为 80 位。已知候选的 Decimal/Fraction 事后误差界不进入生产，也不被描述成在线保证。原高精度脚本与完整失败/未知样例保留在交付研究证据中，生产只使用上述 Double 实现。

这些测试不表示已完成 body/self 接触联合求解、物理收敛或完整成衣。

## 413近屏障谱基值修正（2026-10-27）

真实旧人体衬衫413步在原96次Newton预算内未收敛：最后固定最大力约`1.035083e−6 N`，DOF949反复被报告为下降。原从0运行的412末态、413报告、最后候选与全部case文件单独绑定在`/private/tmp/TailorAssShirt413Diagnosis/input-binding.json`，没有把其兄弟圆裙运行当作已封存。

对真实最后候选与DOF949下一个Double格点，原完整增量分别报告正向`−3.4026556e−25 J`、反向`−2.5458724e−25 J`。80/100位独立完整源/接触叶能量计算给出正向**上升**`+1.4038151e−25 J`；CP另用Fraction/Decimal80/120/180独立确认principal barrier项。主误差来自起点变形梯度与谱基值的低位丢失：相关主伸长距严格上界1.07约`6–9e−7`，基值舍入被gap敏感性放大。不是log1p恒等式缺项，也不能靠排序、平均正反值、visited屏蔽、增加Newton次数或放宽力阈值处理。

本次只修改`GarmentCodeElasticEnergyDelta`的principal barrier增量链：从原实际坐标及原存储shape coefficients开始，使用固定两字EFT/DD保留F、Gram、谱基值、主伸长增量、activation/gap及商的低位。sqrt/除法用有界校正，log/log1p对低位作残差校正。NH、hinge、真实Φ/gradient/Hv、N/S/R、材料和所有路径/最终质量门槛不改。每个primitive保持固定字数；超出显式算术范围、非有限、异常域或不可表示状态仍拒绝。启用barrier时，每个外部取消callback前后及发布前检查nearest rounding；typed取消继续传播。

这仍是浮点**估计**，不是通用能量符号或误差区间证书。它没有把任何未确认项当作0，没有对近静止状态添加Armijo容差。真实949点对barrier误差降到约`1.4e−31 J`，正向完整context恢复上升、反向下降。长期局部夹具`Fixtures/3d-elastic-delta/near-limit413.json`保留原点位hex、原source shape和原双负结果；`ElasticEnergyDelta.swift`同时检查精确shape、完整context符号和每个callback的FPU变更拒绝。

临时副本从**真实412状态**重建生产413一步，保持原N2609、96×400及原source/body/self门槛：37次Newton后接受，R fresh最大力`8.9472212e−7 N`、current-P修正`5.60e−16 m`、Pz残差`5.49e−15`，37个实际静态路径段及同可见mesh人体检查通过。没有载入旧413 inner作为初态，没有产生历史轨迹资格、`Validated`或OBJ，也没有启动新的从0整衣运行。

实际超阈值DOF997的独立一阶/二阶结果同时保留：真实力约`−1.01347e−6 N`，局部Hessian对角约`1.08801e11 N/m`，其连续单坐标最优步仅约0.336 ULP，两个相邻Double格点都上升。source triangle condition约2.03/3.68，并非瘦片退化。修正Δ后生产N通过其他真实坐标/耦合推进达到原门槛，没有把这种格点效应直接标为收敛。
