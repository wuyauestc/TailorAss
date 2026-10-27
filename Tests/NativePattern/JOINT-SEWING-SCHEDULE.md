# Frame 缝合调度与 P 一致性

运行 `python3 Tests/NativePattern/run-joint-sewing-schedule.py --output <新目录>`。
可用 `--model-source <既有Models快照目录>` 重放明确版本。runner只构建已经隔离的
真实NativeSparse薄模块，避免其它Package worker尚未冻结的新模块混编。

先将原 `JointPreconditioner.swift` 仅重命名main类型作为helper执行，不修改原测试。
其默认distanceTarget的synthetic/realInitial/realR16三个固定CSC+Double数值hash
必须完全不变；原完整hinge-GN/真Pz/真实source回归也继续运行。

新调度控制为3个起始k（.001、1、1e8）×8个r，从0、接近0、中间值、接近1到1。
目标始终为0；r0直接原initial、r1直接原终态k，端点逐Double位匹配。中间指数
是Double超越函数近似，可有ulp级舍入，并不宣称所有中间值字节等于实数运算。

对同源、有缝/无缝P作增量，独立计算 `k AᵀA ⊗ I`，包含完整barycentric附着点
及所有交叉项；再对真正rawH作相同增量。较弱k时从较大基P相减会损失位数，
测试使用表示矩阵相减的128eps×操作量级界，不是给物理/Armijo加能量容差。
4个精确重合点证明zero-target模式仍为smooth kI；旧positive-target奇点继续明确
拒绝。非法initial、NaN ramp等不放行。

r1的P全部数值、实际Phi、gradient和rawHv逐Double位恢复原distance最终模型。
稳定能量差的两个算法并不要求字节相同：旧radial长度增量式与新直接quadratic
式代数上相同，但可能差1ulp。对实际已舍入的x/y、原Double row coefficients和
k，用独立Decimal80/100计算二次缝合势差，正负两个可分辨步骤验证符号与误差。
这是专项数值oracle，不是任意驻点上的普遍符号保证，不进入生产线搜索。

首轮失败（额外要求Δ算法逐位相同的过严测试）完整保留在
`/private/tmp/TailorAssJointSewingScheduleFinal`；修正后的独立验证位于
`/private/tmp/TailorAssJointSewingScheduleVerified`，J SHA139e186…64e1c，
P SHA2aa195f…0a34c，与旧CP pre-homotopy证明是不同快照。

该测试不运行新的Newton或物理步骤，不改变N/S/J/P/CP，不证明成衣收敛。
低载荷停止条件的只读审查保留在 `/private/tmp/TailorAssStoppingReview`。
