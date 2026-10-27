# 保守空间索引：完整布片间隙准备

`GarmentCodeRigidClothClearance` 使用每裁片 3D BVH，避免在整个裁片包围盒相交时，反复遍历内部所有三角面的笛卡尔积。这里只优化初始逐片刚体间隙准备，未改变纸样、mesher、缝合、求解器、面料、人体、接触阈值或原预算数值，也不表示三维成衣已完成。

## 实际问题与独立候选覆盖

层裙真实 hem 修复后，8 项原构造首点拒绝全部消失，6 项准备成功；default 的 Circle→Asymm、Asymm→Asymm 在后续准备触及 10,240,000 三角面对预算。

只读 observer 原样复现了两次失败。两个计数均为 pair=10,240,001、clip=0、projection BVH=0；实际尚未做源足迹精裁。旧代码在每次 `inspect` 的逐面 AABB 排除之前，就为整个笛卡尔积计费，未移动裁片之间也重复扫描。错误中的“与源足迹裁剪”只是共享预算名称。

对所有 7 个真实已捕获 `inspect` 状态（含被中止轮的完整状态），独立 Python prototype 与完整笛卡尔参考逐 `(i,j)` 比较原 `Face.distanceLowerBoundSquared <= target²` 候选，集合完全相同：

| 两款实际状态前缀 | 完整笛卡尔对 | 真正原面 AABB 候选 | BVH 叶面比较 |
| --- | ---: | ---: | ---: |
| Circle base，3 状态 | 11,886,184 | 4,759 | 14,039 |
| Asymm base，4 状态 | 11,815,764 | 1,527 | 6,424 |

这只是只读候选覆盖证明，没有让旧失败状态越过原预算，也没有把截断 inspection 当 clear。

## 保守性与顺序

每节点以原面坐标 min/max 包围全部后代，按中心坐标及原面 ID 的确定全序中位分裂，叶大小 8。

正间隙模式的节点距离下界，对各减法、非负平方及非负加法分别取 `.nextDown`，再将负下界截为零。节点盒包含所有后代面盒，浮点运算单调，因此该下界也不会大于任何后代原 Float64 面盒距离结果；只有下界严格大于原 target² 才剔除。阈值等号继续保留。crossing-only 模式保持原闭包 AABB 重叠语义。

逐原面 i 查询另一裁片树，候选 j 按原 ID 排序，随后仍执行原面盒过滤、proper/coplanar 判定和全部六 VF／九 EE 距离判据。因此源冲突、支持选项、刚体移动顺序不因树遍历顺序改变。同片原语检查、源足迹裁剪与支持计算保持原算法，没有邻接面或接缝宽泛豁免。

## 预算、取消与内存

- 构建节点、扫描构建面界、每次排序比较、每次查询节点都计入原 `panel+bvh` 上限 10,240,000；叶面比较计入原 `pair+clip` 上限 10,240,000。两类预算分别守门，没有把空对变成无限免费工作。
- 构建／排序／节点访问均定期检查取消。排序闭包可抛出，预算或取消立即终止，不在取消后继续完成整个排序；所有工作区只属于当前调用，没有全局缓存或诊断状态晋升。
- 额外节点容量、order、排序临时区、单次候选／查询栈、容器开销及递归栈按保守公式预检固定 32 MiB；节点和候选数量另受完整源面数限制。这是额外容器的保守计费，不是实测 RSS，也没有提高原 source triangle cap。
- proof 新增可选的 build/sort/node/leaf/memory 字段。原 `projectionBVHVisits` 继续只表示源足迹索引；所有索引工作仍进入同一个原总预算。

## 当前验证与版本范围

生产 RCC SHA：`505a6419c0be3d7f8920dd8fea486c899898922f1ca81f51a151df48594cb55f`。

新 8 项均实际重新执行 S.capture→后台 S.prepare→R.prepare，8/8 ready。两原预算失败在原 cap 内完成：Circle pair=44,604、panel=2,227,057；Asymm pair=33,191、panel=1,641,236。旧 6 项全部原位置、rest、mass、面／独立映射、body 逐位相同，整个 sewing Plan 字节相同。

8 项全部源边、源面积／lumped mass 和 barycentric attachment 由独立脚本复核；独立 exact Fraction 静态相交与三轴 parity 覆盖全部 134,630 个顶点／源边中点／面中心样本，无 proper/coplanar/非拓扑触碰或未知，全部在实际人体外。复用原独立距离 oracle 又检查全部 VF／EE：跨片最小距离 >50 µm，同片无共享原语最小距离 >0，零距与 10 nm 内原语均为零。该 Mac oracle 的 long-double mantissa 实际为 53 位，未声称是扩展精度。

`RigidClothClearance.swift` 新增真实 split BVH 网格、原 gap 的 nextDown／exact／nextUp、预算、取消原子性、临时内存及取消后重新准备控制。10 组解析场景、25 个显式拒绝已通过。

原 211 输入及 633 个旧初始化模式签名全部通过，无 unexpected failure 或 known incomplete source。独立正间隙复核的跨片最小值为 50.000999999994 µm，同片非邻接最小值约 0.263847 mm，零距与 10 nm 内原语为零。独立人体／布片 proper crossing、共面正面积重叠、inside 或 ambiguous 均为零。实际进程的编译、解析＋211、独立距离三个命令退出码都为 0。

另与既有 `TailorAssNativePositiveClearanceFinal` 的 211 项实际正间隙结果直接比较：全部源 SHA、完整最终 state SHA 及完整接缝 plan SHA 也相同，覆盖旧第四种 positiveGap 模式的实际输出，而非仅比较旧三个模式。

本次准备／211 冻结使用旧 Geometry（根任务后续修复 circleArc π 分支之前）与既有其余模型；8 项准备明确链接 sealed105 native。根任务的完整 App Release +111 native，以及整衣物理长跑，是另外的冻结组合，不能混称本报告验证了它们。

实际准备和独立报告：`/private/tmp/TailorAssLevelsClearanceBroadPhaseFirst-czkuwowe`。完整 211／解析回归：`/private/tmp/TailorAssRCCBroadPhaseRegression-uytha4di`。原 observer：`/private/tmp/TailorAssLevelsClearanceBudgetObserver-uay_jz_m`。这些均为准备或静态几何证据，不是稳定成衣、个人合身或 iOS 运行证明。
