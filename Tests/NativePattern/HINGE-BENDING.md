# 同源裁片内部的离散弯曲能量

`GarmentCodeHingeBending.swift` 是独立能量模块。它没有接入旧仿真、面料预设或 App 路由，不修改纸样、质量、接缝、自由度或 pins。导数测试通过不代表联合求解器已稳定，更不代表已生成完整成衣。

## 能量、单位与来源

采用 [Tamstorf / Disney 2013 官方技术报告](https://media.disneyanimation.com/uploads/production/publication_asset/75/asset/WDAS_TR_201307.pdf) §2 Eq. (1)、(4) 的 Discrete Shells 约定：

\[
E_b=k_b\sum_h w_h\theta_h^2,\qquad
w_h=\frac{3L_{0h}^{2}}{A_{01h}+A_{02h}}.
\]

公式没有额外的 `1/2`。`L0`、两邻面的面积都从不变的源网格计算，求导时保持固定。源纸样是平面，静止角 `theta0=0`，准备阶段逐 hinge 检查这一条件。代码独立实现，不复制第三方实现。

`k_b` 通过 `Material(bendingStiffnessNewtonMeter:)` 显式传入，单位 **N·m**，可为零，必须有限、非负且不超过 `1e12`。测试值 `0.0002 N·m` 只是实验系数，没有经过实物标定，也没有映射到现有三档面料。不能直接把它等同于工程弯曲刚度 D。权重无量纲，能量是 J，梯度是 N，Hessian 是 N/m。

## 分组与源拓扑契约

生产接口只接收明确的完整源裁片分组，不从连通性、空间坐标或缝合计划猜测裁片身份：

```swift
let groups = prepared.panelBindings.map {
    GarmentCodeCircleDrape.PanelGroup(
        panelID: $0.mesh.panelID,
        vertexIDs: $0.vertexIDs,
        triangleIDs: $0.triangleIDs)
}
let bending = try GarmentCodeHingeBending.Prepared(
    referencePositions: prepared.cloth.referencePositions,
    referenceTriangles: prepared.cloth.referenceTriangles,
    panelGroups: groups)
```

调用者应使用已经过 `PreparedInput` 来源检查的源数据。数学模块自身不认证 native 来源或 canonical SHA。它会再次检查：分组名称唯一且有界；所有源顶点、三角面各恰好归属一次；面内三顶点与该面的分组一致；顶点全部实际被面使用；三角面不重复、不退化；共享边恰好有两面且方向相反。边界只有一邻面，直接保留为自由边，不建立弯曲 hinge。重合但 ID 不同的接缝节点不焊接，未完全缝合的跨片接口不增加弯曲约束。

每个 hinge 保存原顶点 ID、两个源面 ID、源长度、源面积与固定权重。没有用旧 `bendingSprings` 的跨面异侧顶点距离代替二面角。

## 有符号角与精确导数

相邻面顺序是 `[x1,x2,x3]` 和 `[x2,x1,x4]`。设

\[
e=x_2-x_1,\quad v=x_3-x_1,\quad w=x_4-x_1,\quad L=|e|,
\quad N_1=e\times v,\quad N_2=w\times e,\quad n_i=N_i/|N_i|.
\]

\[
\theta=\operatorname{atan2}\big((e/L)\cdot(n_1\times n_2),\ n_1\cdot n_2\big).
\]

平面角为零。此符号约定下，`e` 沿 `+x`、`x3` 在 `+y`、`x4` 在 `−y` 时，将 `x3` 向 `+z` 移动会使角度为负；将 `x4` 绕 `+x` 旋转 `a`，则 `theta=a`。

角度的精确梯度 `q_i = ∂theta/∂x_i` 是

\[
q_3=-LN_1/|N_1|^2,\quad q_4=-LN_2/|N_2|^2,
\quad a=(e\cdot v)/L^2,\quad b=(e\cdot w)/L^2,
\]
\[
q_1=-(1-a)q_3-(1-b)q_4,\qquad q_2=-aq_3-bq_4.
\]

因此 `gradient(E_h)=2*k_b*w_h*theta*q`。`angle(positions:hingeID:)` 返回有符号角和单位为 `1/m` 的四点角梯度，避免把角梯度误标为力。

`hessianProduct(...mode:.exact)` 解析计算

\[
H_h d=2k_bw_h\big[(q\cdot d)q+\theta Dq[d]\big].
\]

代码直接对上述 `q` 求方向导数，包含边长、法向、面积分母和 `a,b` 的变化，没有将法向或长度冻结。`mode:.gaussNewtonPSD` **明确是近似**，只保留 `2*k_b*w_h*(q·d)*q`。二者在平直静止状态相同；折弯时精确 Hessian 可以不定，不能直接假设可由只接受 SPD 的线性求解器求解。单 hinge 谱测试中最小精确特征值约为 `−0.224984 N/m`。

平移时梯度总和为零，旋转时总力矩为零。带应力状态的精确旋转关系是 `H(ω×x)=ω×gradient`；不能把一般折弯状态的所有瞬时旋转都误称为 Hessian 零空间。

## 有效域、取消与预算

当前边长、当前三角面叉积范数必须分别大于各自源值的 `1e−8`；源叉积范数必须大于最大源边长平方的 `1e−12`。坐标必须有限、使用米且模长小于 `100 m`。发生退化时返回错误，不在分母里填 epsilon，也不把无效状态压成有限能量。

`atan2` 在 `±π` 的分支上，`theta²` 连续但不可微。默认明确拒绝距分支不超过 `1e−6 rad` 的状态；不截断角度或力。测试分别从两侧逼近 `π−0.001 rad`，并验证分支排除带。其他连续角模型属于另一个需要单独设计的能量策略。

硬预算是 20,000 顶点、40,000 三角面、60,000 hinge、128 裁片；调用者可收紧。构建、能量和 Hv 的循环定期检查取消，传播 `CancellationError`。构建复杂度为 `O(T+E log E)`，能量与矩阵自由 Hv 为 `O(V+H)`。这些数值域检查不能替代原接缝、源应变、人体和自碰撞验收。

## 永久固定样例与回归

运行：

```sh
Tests/NativePattern/run-hinge-bending.sh
```

可设置 `GARMENTCODE_HINGE_OUTPUT`、`GARMENTCODE_HINGE_KEEP_SNAPSHOT=1`，或用 `GARMENTCODE_HINGE_PYTHON` 指向带 NumPy 的解释器。runner 将所有编译依赖一次性复制到 `/private/tmp`，严格并发编译，保存完整 SHA 清单。日常回归只读取仓库 fixture，不依赖临时上游目录或旧 cone 的编号。

`Fixtures/3d-hinge` 保留：

- canonical 完整纸样 `28eb56b2ec46feddde570c300896cd6422045e6d119d0a2af11f667ae7604a35`；
- 实际同一编号的完整 plan，SHA `5616e42273ff9ee28f19793f28f2a23b2efa95be46f8d417e1e9203fe7227e05`；
- 2000 个原参考顶点、原始各片刚体位置、3472 个原面、零 pins，以及显式完整分组。

fixture 生成器只在归档阶段恢复分组：原拓扑分量必须被真实 plan 的完整边界唯一命名，而且每个边界采样都按 canonical 源曲线解析核对，每条边界 segment 的原面 ID 都验证一致。16 条源边的最大点误差约 `4.16e−16 m`。这个归档过程不进入生产接口。归档和逐次验证指令见 `GenerateHingeBendingFixture.py --help`。

实际图共有 **4948 个片内 hinge、520 条无 hinge 的边界**：`skirt_back=2408`、`skirt_front=2384`、`wb_back=75`、`wb_front=81`。旧距离弹簧列表为 4814 条，没有复用。原平纸和各片刚体摆放的弯曲能量均为零。真实导数测试只施加一组小的解析曲面位移，没有运行物理。

测试覆盖解析角、12 个单 hinge 梯度分量、精确 Hv 有限差分、Hessian 对称、刚体和尺度协变、精确旋转恒等式、GN PSD 与精确项差别、网格细分、正反分支、退化、无效材料、无效/缺失/重复/跨片分组、面顺序、取消及真实图预算。真实源还覆盖 3 个全局方向步长、49 个局部顶点方向，以及独立 NumPy 的能量、权重和谱检查。参考结果为：真实 Hv FD 相对误差约 `4.72e−11`、方向梯度 FD 约 `1.28e−8`，49 个局部 Hv 最大约 `4.09e−10`。

## 需要保留的限制

将源和当前几何同时放大 `s`，权重和能量不变，梯度变为 `1/s`，Hessian 变为 `1/s²`，测试对此逐项验证。有限分辨率下加密网格不应被声称为能量完全不变：固定方向矩形网格圆柱测试收敛到该网格族的离散极限。

独立 45° 曲率方向测试收敛到不同能量，暴露此基础 hinge 模型的三角剖分和方向依赖。因此没有宣称任意重网格不变、已校准的各向同性连续介质极限或真实面料参数。未来联合 Φ 应使用真实能量和梯度、明确标记精确或 GN 线性化，维持有效域及线搜索，再重新通过完整源/接缝/人体/自碰撞门槛；本模块回归本身不证明这些物理条件。
