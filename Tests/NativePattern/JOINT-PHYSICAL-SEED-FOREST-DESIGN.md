# 已提交时间分区复用：实现与验证

前版S137/R794/Nbc91冻结记录保留。S d81／R3359／N2609冻结版本已实现以下控制策略，不改变质量、材料、力阈值、完整路径或24宏步稳定要求；通过整合控制后的两款完整初态运行现已结束，均未通过整衣验收。圆裙接受1130步，第1131步为`Newton lineSearchFailed`；衬衫接受412步，第413步为`Newton newtonBudget`。终态交付位于`/private/tmp/TailorAssJointSeedForestFull/delivery-manifest.json`，SHA256为`6a818d956cf762ddbbcc3344a373f974ec579c1847fe4d74a891d8ee2c4d44e5`。该控制策略已包含在后续App817构建中，安装与界面检查另列证据。

## 实证与范围

实际923生产诊断的9个attempt中，4个失败parent分别耗时46.6007、37.0034、124.2367、68.1924秒，合计276.0333秒；5个成功叶合计6.2310秒。该结论来自 `/private/tmp/TailorAssCircle923AdaptiveProduction/result/actual-physical-attempts.json`，不把最终R验证耗时混为Newton成本。

将上一**完整提交**宏步的实际分区作为下一宏步的初始seed forest。它只提示时间尺度；不缓存或复用位置、速度、力、P因子、接触候选或CCD能力。每个实际叶仍有自己的真实tau、预测、m/tau²、指数阻尼、端点载荷、原N收敛与完整source/body/self chord检查。

## 控制状态与原子边界

新增不可变 `PhysicalSeedControl`，由Session私有持有，包含：

- policy版本／模式（旧rootOnly或新committedPartition）；初版growth明确为none。
- baseDt位模式、最大depth、source SHA、body geometry SHA、linearization source身份，以及绑定当前会话全部不可变材料／数值配置的contextIdentity。不同会话不能沿用该控制记录。
- 下一宏步使用的有序dyadic seed spans、ticksPerMacroStep、来源已提交宏步编号及该记录指纹。
- 若以后有增长／回退冷却计数，它也是本控制状态的一部分；不是物理时间或quiet次数。

物理 `State`的x/v/completedSteps/quietCount可以继续原字段；必须将其与controller组成同一逻辑提交快照。`AcceptedFrame`同时保存previousControl、usedSeedRoots、acceptedControl及真实physicalLeaves。R的latest和quiet链需同时核对物理状态与控制状态，不能让独立可变cache绕过取消原子性。

宏步入口复制before物理状态和beforeControl。仅当所有seed及细分叶完成、最终取消检查通过后，更新x/v、completedSteps、journal、quiet窗口和nextControl。next seeds为本次真实接受叶的分区；失败／取消即使已完成若干前缀叶，也保留beforeControl及所有public状态逐位不变。

第一动态宏步没有上一动态分区，使用单根[0,D]。静态480次配置推进不产生物理时间seed。新prepared/source/body/材料/baseDt/depth/policy不匹配时不得沿用旧seed；显式重置root或拒绝恢复，记录原因。

## 有界forest与R独立验证

最大depth仍3，D=8；每个seed是有序、对齐、宽度为2次幂的闭时间区间，其内部按半开约定归属唯一，全部seed不重叠且覆盖[0,D]。执行顺序固定为seed从左到右，每个失败seed只递归细分自己的时间区间。成功叶不可跨seed边界。所有子步仍从真实前叶x/v重建方程。

设初始seed根数K、最终接受叶数L。每个根的完整二叉细分树有2Li-1个真实attempt，故：

`attempts = 2L - K`，`1 <= K <= L <= 8`，全局最多15。

当前R的2L-1只适用于K=1，不能继续使用，也不能补写未执行的failed parent。R须独立核：

1. used seeds属于beforeControl（或明确的root reset），source/config/记录来源一致。
2. seeds及leaves各自完整对齐覆盖[0,D]；每leaf完全属于唯一seed，所有seed至少有一叶。
3. 每seed的叶形成真实dyadic细分，attempt计数与2L-K一致且<=15。
4. 实际max depth由最小叶宽计算，与report一致；configured depth不冒充实际深度。
5. 每叶的bitwise x/v链、tau/predictor/端点load、原fresh g/P/Pz、原完整路径及独立表面检查全部保留。
6. 宏末位置和速度等于末叶，宏物理时长恰为baseDt；没有执行的宏外弦不是物理轨迹。

建议AcceptedFrame保留紧凑attempt-tree ledger：seed索引、span、parent/深度、接受／失败原因及实际成本。失败parent完整坐标只留在本次有界诊断，不必进入24宏步journal；ledger不能伪称这些parent是物理轨迹。

## 报告、历史JSON与922来源

StepReport新增可选policyVersion、usedSeedRoots、seedRootCount、seedOriginStep、seedReused；physicalSubstepAttempts仍是实际执行数。newton明确为末叶，g/P/source/speed等聚合继续区分worst与末叶。wall成本只计一次，simulatedSeconds仍是已提交完整宏步数乘baseDt。quiet必须所有真实叶fullgravity/fullysewn且满足原阈值，24宏步仍为0.1秒，不能按短叶次数提前完成。

旧JSON缺新字段时只能解释为旧rootOnly数据，不能默认为新forest且假设K=1。无法判定的policy／seed来源应拒绝正式恢复，或显式重置root作为新诊断。JSON只是数据，不能反序列化得到新的私有AcceptedFrame／Validated能力。

历史922确有可信seed来源：

`/private/tmp/TailorAssJointPhysicalSubsteps129Full/requested2400/circle-straight-band/circle-straight-band/last-accepted-frame.json`

其accepted.completedSteps=922，真实叶为[0,1]、[1,2]/2；同目录physical-attempts-0922.json为失败整步加两个成功half。核原manifest、source/body/config、完整末状态位模式和记录关系后，可无损映射为[0,4]、[4,8]/8，K=2。仅有last-accepted-state的x/v不能反推出这一分区。

不能将后来923诊断得到的5叶分区冒称来自922。以922真实K=2重放923，只能预先省掉原[0,8]整步约46.6秒；其他失败parent仍可能发生。923真正提交后，924才可合法继承其5叶分区。新诊断不自动取得原始0起完整历史的验收资格。

## 首版策略与必要控制

先只继承／细分，不自动coarsen。它是恢复成本控制，不是带误差界的自适应积分器；更小tau改变离散轨迹，仍须新的完整运行证据。后续若加入增长，需独立有界、可重放的显式policy，只能在下一宏步入口提议，不能在已执行前缀后合并时间或复用旧证书。

必要测试包括：

- rootOnly精确保持现有K=1轨迹和2L-1；首次动态root reset可复现。
- 922真实half映射到8分母，无坐标／载荷变化；缺来源或用923未来信息作seed须拒绝。
- K=5全部成功只执行5次；其中一quarter细分后L=6只执行7次，完整forest计数真实。
- 假2L-1、跨seed叶、空seed、间隙／重叠／不对齐、错误来源／dt/config/depth全部拒绝。
- cancel或后seed失败时，物理State、hint、journal、quiet及冷却计数都不提交；区间[6,7]/8控制按实际区间表达，不根据标签猜叶ordinal。
- 24小叶不构成24宏quiet；每个真实叶原KKT／完整路径／表面门槛不变。
- 所有预算／未知／取消仍不clear；不挪用省下的成本增加N迭代或改变材料／厚度／缝合。

## 当前整合证据

`/private/tmp/TailorAssJointSeedForestControls/`冻结45个生产模型，实际以Swift 5、完整严格并发和warnings-as-errors编译，复用逐字节相同的Native129已验证归档。编译59.32秒、控制运行4.72秒，两个命令真实退出0。57项纯数据控制通过；圆裙与腰头、带袖衬衫分别从真实初态执行首个静态配置步，并重新计算完整源／人体／自接触路径与受力判据，取消和预算失败保持物理状态、分段控制、记录及稳定窗口不变。这部分不包含新的动态forest执行验收。

根侧已核对全部冻结源与原生依赖、实际控制结果和两个首步的fresh判据，封存750文件，`delivery-manifest.json` SHA256为`13ca76ef70dacea754a4ae46fbe2b89d99535e4c9bfefb68eb5b69c7a407cc7e`。同一binary SHA256为`654616e712a43b05f54064f64e44b4537e9d0ec99ef9cbe0b22f23187d82c5f8`。

该binary已在`/private/tmp/TailorAssJointSeedForestFull/`唯一启动两款从初始裁片开始的完整运行，最多2400宏步，未加载任何checkpoint。原480次静态配置、240次重力渐进及24宏步稳定要求保持。真实481兼容、922来源分区、923→924、低深度拒绝和深层取消另做专项；完整运行和专项目前均未给出最终结论，不应把控制进程退出0视作整衣已经通过。
