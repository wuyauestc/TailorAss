# 完整源整衣接触与连续推进

`GarmentCodeJointGarmentObjective` 将同一源的惯性、膜、主伸长障碍、内部铰链弯曲、真实接缝、人体和布片自接触相加。实际 E、梯度和 Hessian 乘向量都包含全部启用项；完整接触块的 PSD 模式仅供预条件使用，不替换真实导数。正式入口接收 `JointInput.Prepared`，再次核对独立自由度、参考三角系数、全部面和人体身份。

接触库保留固定版本 IPC 的 signed 面积组装、负校正项、参考边 mollifier 和原距离/障碍函数。本地builder修正了边序交换时固定距离类型未同步转换的身份错误，详见下节。布片的双方顶点均运动，接缝的独立顶点不因位置接近而被当作拓扑相邻。同片共顶点的面也只排除真实共享原语，不整面对豁免。当前 Package 的105项实际测试和 iOS17/Simulator 真 Swift 静态链接已有冻结证据，详见 `NativeClothCollision/README.md`；这些证明不等于完整衣服已经稳定。

```sh
python3 Tests/NativePattern/run-joint-garment-objective.py
python3 Tests/NativePattern/run-joint-simulation.py --steps 8
```

第一项包含人体、自接触、膜障碍、非零弯曲和缝合同时激活的联合导数对照；修复后重新运行的三组方向梯度/精确Hv有限差分通过。实际带袖上衣保留8片、1,732个独立顶点及444行接缝；修正参考的初态560个自接触项中有418个负校正项，完整梯度与原始Hv均通过独立完整builder对照。旧391项／314负项来自含同一身份错误的历史参考，原文件保持供追溯。导数测试不推进时间，也不产生验收成衣。

## 定向接触项身份修复

Circle218及Shirt175两处线搜索拒绝均已追溯到相同的接触项标识问题。原完整builder将EE边对当作无序键，但缓存的固定距离类型仍按有序边解释；反向的负校正会与另一物理距离函数合并。圆裙在PE activation处、上衣在mollifier阈值处分别产生有限能量跳变，不能通过增加迭代或放宽Armijo解决。

两个本地wrapper现共同规范化实际边序、dtype和键，原物理参数、源度量、候选与距离叶保持。纠正后的完整官方参考与独立保留方向、不合并EE的全项求和一致；旧上游和旧移植数值保留为历史记录。原生91项测试及两平台92条实际命令通过，冻结交付 `/private/tmp/TailorAssIPCOrientationIdentityIntegratedFinal/delivery-manifest.json`；其中原summary的历史“original golden verified”键只表示旧文件哈希，新数值含义见同目录 `clarified-summary.json`。

生产整衣目标重新通过联合导数、完整源绑定、初态560项原始力及Hv检查（`/private/tmp/TailorAssJointGarmentOrientationFixed/summary.json`）。实际Shirt原始Hv与纠正独立参考的最大差约 `1.27e−11 N/m`。Newton数学／真实人体／路径／取消回归亦通过（`/private/tmp/TailorAssJointNewtonOrientationFixed/summary.json`）。接下来完整生成从真实初态重跑，不能把纠正前的接受前缀接到新物理目标上。

弹性线性化仅缓存同一源和同一实际迭代位置的常量。源 UUID、实际坐标、材料及障碍域均须相符，旧位置/其他源缓存会被拒绝。联合 Hv 已与未缓存原公式逐 Double 位比较；真实接触仍用原始局部 Hessian。能量线搜索使用稳定弹性/惯性/缝合增量；接触增量现采用下述独立的稳定计算。全部仍为有适用域的Double估计，不声称普遍正确符号。

## 障碍预条件、稳定增量与自碰撞精度补证

真实圆裙第250步的原线性求解曾达到400次CG预算。诊断确认最紧三角形的主伸长障碍曲率约为原P的6,533倍。生产P现加入形变梯度空间的非负谱模式，再按真实源系数拉回全部9个自由度；真实能量、梯度和原始Hessian公式保持。实际最差障碍/P比降至约0.999847；独立高精度及完整旧回归通过，但这一比值本身不是非线性收敛验收。见 [PRINCIPAL-BARRIER-PRECONDITIONER.md](PRINCIPAL-BARRIER-PRECONDITIONER.md)及冻结交付 `/private/tmp/TailorAssBarrierPreconditionerFinal/delivery-manifest.json`。

接触叶能量先舍入再相减会丢失接近收敛时的变化。新owned增量模块对同身份、同面积权和兼容距离分支使用距离商、叉积及log1p增量；结构或有效分支改变时显式回退原完整块相减。1,705个真实叶与25个解析样例通过80/100位坐标对照，原接触E/g/H保持。详情见 `NativeClothCollision/CONTACT-ENERGY-DELTA.md`。当前联合导数及原始Hv检查亦通过，记录在 `/private/tmp/TailorAssJointGarmentStableContactAndBarrier/summary.json`。报告中的旧`bodyRoundedBlockDeltaJoules`／`selfRoundedBlockDeltaJoules`仅为诊断，实际线搜索读取`contactIncrement.body.deltaJoules`／`contactIncrement.cloth.deltaJoules`。

两项改进合并后的完整初态运行保留于 `/private/tmp/TailorAssJointCombinedFinalProductionFull`：圆裙＋直条腰头接受386步，第387步自碰撞路径检查拒绝；带袖上衣接受342步，第343步同样拒绝。两款仍处于静态装配，未生成`Validated`或导出。对实际保存的最后候选重新检查，原生CCD均因保守精度限制返回未知；独立精确分数证明整段最小间隙分别至少约0.780354µm和2.229189µm，严格大于原零下界。

生产SelfGuard现只对原生保守候选或精度／预算未知候选，调用既有的有界整段欧氏分离证书；证明分离后继续核验其余全部特征。未知、真实接触、取消或预算失败仍拒绝，源面域、邻接排除和物理下界保持。上述两个完整查询的702／1,989个特征均检查完成；105项Mac测试、101条实际命令及双SDK最终链接通过，见 `/private/tmp/TailorAssSelfEuclideanSupplementIntegratedFinal/delivery-manifest.json`。新的完整推进从初态重新运行；这些路径补证不是整件成衣验收。

`GarmentCodeJointSimulation` 从完整正间距初态开始，固定480次无重力静态装配、240步重力渐入、1/240秒物理时间步，之后有界下垂至稳定。布料质量、源长、终态顺应度和零人工固定点保持，没有位置后投影。静态装配与真实动态轨迹采用下述不同且显式记录的契约；每段实际移动都必须完成全部源主伸长、人体和自碰撞检查。全部源三角边及接缝间隙另测量；每步完成全部检查后一次提交状态，取消、未知路径、预算或不收敛都不提交部分结果。

## 静态装配轨迹与物理时间步

后续 105 项库的完整初态运行实际接受圆裙＋腰头 689 步、带袖上衣 402 步，随后分别在 690/403 步线搜索停止。圆裙已推进 209 个物理步、约 0.871 秒，尚在重力渐入；上衣仍在静态装配。原全部状态和失败轨迹保留于 `/private/tmp/TailorAssJointSelfEU105ProductionFull`，没有已验收输出。

这两个失败的独立诊断带来两项生产修正。Newton 在原 CG 方向的有界线搜索耗尽后允许尝试当前 P 梯度方向，仍逐候选检查原能量、形变与碰撞；同一上衣失败内部状态收敛，fresh outer 整帧对照则中新旧 N 都通过，不能把后者归因于后备。圆裙整物理步原有保守拒绝由相关运动法向的 Bernstein 区间证明补足，全部 1,552 个特征通过完整路径检查；111 项原生包、独立精确分数与两 SDK 客户端链接通过。两项都不放宽物理下界或最终验收，也不证明完整成衣通过。当前唯一新运行从初始裁片开始，冻结目录为 `/private/tmp/TailorAssJointFSC111PGradientFull`；运行状态以实际终态文件为准。

这轮 Native111＋P 梯度后备的完整运行已结束：圆裙实际接受 689 步，在 690 步线搜索失败；带袖上衣接受 404 步，在 405 步线搜索失败。交付清单 SHA256 为 `53cfbebaad6e63c09db4ef1296dd07f0c59e1e61690e6f02d10f1afb00299ffe`。圆裙仍只推进 209 个真实物理步，上衣仍在静态装配，两者都没有已验收输出；保留所有实际轨迹和失败候选。

新圆裙失败路径出现约 3.4e−16 m 的严格分离，原 Double 区间在多项式相消时无法确认。原生库现加入有界精确 expansion 后备，针对储存的二进制端点形成三倍三次 Bernstein 系数，再做同一原区间的 dyadic 细分；保留深度 12、8191 节点及原物理下界，精度、容量、运算或内存预算不足仍拒绝。实际完整 117 项测试、199 个精确 EFT 等式、9 条新运动与独立 Fraction 证明、两 SDK 实际客户端链接通过。保存的内层／整步两条 Self 查询分别完整检查 626／1552 个特征并通过；这只修复已保存路径的证明能力，不代表后续整衣收敛。冻结交付 `/private/tmp/TailorAssFSCExpansionIntegratedFinal/delivery-manifest.json`，SHA256 `73e08acadc92dfc0cd98eee1019b41875a1608521a7a446f78f1b57ef28a25b0`。

带袖上衣 405 的实际受力为 1.463819e−6 N，超过原门槛。两个单坐标相邻可表示数候选通过真实能量下降、原受力／当前 P 指标与完整源／人体／自碰撞检查，说明存在可行下降步；这些只是固定候选证据，没有提交或恢复旧仿真。通用有界求解后备另行实现与验证，新的完整运行必须从初始裁片开始。

静态阶段使用 `configurationPolyline`：按顺序保存 Newton 实际接受的每一条线段，并逐段绑定真实端点及完整源形变、人体、自碰撞证书。最终检查重新计算全部线段的三个证书，要求首尾连接、覆盖整个已接受装配过程。没有实际执行的“整次装配起点到终点直线”不充当运动轨迹。原来的 `m/(2dt²)·|x−predictor|²` 保留为本次静态装配的近端正则项；该阶段的位移除以 `dt` 只记录为配置变化率，不能算物理速度或模拟时长，也不能计入连续24步稳定验收。

重力渐入与下垂阶段固定使用 `physicalLinearStep`，仍须检查真实整时间步起点到候选的完整直线路径；局部 Newton 路径也必须安全。该模式没有静态分段替代，真实速度仍为本步位移除以原时间步。低层 Newton 默认值保持物理直线模式。这里未实现自适应物理子步，也未改变惯性、阻尼、真实能量／梯度／原始Hv、几何门槛或最终24步验收要求。

轨迹契约的数学回归、两个实际完整源前8次装配，以及结果边界的真实分段链、逐段重新检查、取消原子性及“静态变化率不能标作物理速度”负控已通过。完整静态装配／重力／稳定运行仍需单独通过，前缀通过不代表整件成衣通过。

该契约下的第一轮完整预算运行分别请求最多2400步：圆裙＋直条腰头实际接受153次装配，在第154次达到64次Newton预算；带袖上衣实际接受146次，在第147次同样达到预算。两个被拒绝步骤中的64条已接受局部路径均通过源形变、人体与自碰撞检查；停止来自非线性求解尚未收敛。两款实际动态时间均为0，尚未进入重力阶段，没有输出已验收成衣。原始运行、每步分段轨迹与结果保留在 `/private/tmp/TailorAssJointResultRequested2400Polyline`，程序退出0只表示完成了测试，不代表成衣通过。

随后确认主伸长边界附近的 Weyl 充分界将安全的旋转步长过度缩小。生产求解器改为先提议完整步长，再沿用位移上限、严格能量线搜索及实际整段形变／人体／自碰撞检查；未放宽力、位移或几何验收。原两个失败步骤的固定输入A/B对照分别在20、27次迭代通过，细节见 [JOINT-BODY-NEWTON.md](JOINT-BODY-NEWTON.md)。

修改后的完整源从初态重新运行，记录在 `/private/tmp/TailorAssJointResultActualProposalProduction`：圆裙＋直条腰头实际接受217次装配，第218次线搜索拒绝；带袖上衣接受163次，第164次达到64次Newton预算。两款仍未进入重力阶段，没有返回 `Validated` 或 `Output`。圆裙第218次末轮的微小候选中，自接触能量增加约 `3.824434161e−7 J`，该增量没有随步长缩小消失，原始官方 IPC v1.6.1 完整 builder 也复现了同一跳变；后来定因和修复见上节，原始失败数据不改写。跟踪记录为 `/private/tmp/TailorAssJointCircle218Trace`，官方重放为 `/private/tmp/TailorAssCircle218OfficialReference/official-canonical-order.json`。

带袖上衣第164次的独立诊断允许128次迭代，实际在71次收敛；重新计算的原力／当前P修正／Pz残差、全部71段路径及独立人体检查均通过。它仍是接缝未完成、无重力的单个装配步骤，未晋升为成衣。依据该工作量，生产Newton默认及允许上限改为96，CG上限400、线搜索32次及所有物理／几何门槛保持；最坏单步工作上限增加50%，不会强制已收敛步骤继续迭代。既有数学、真实人体接触、路径拒绝和取消检查通过（`/private/tmp/TailorAssJointNewtonBudget96/summary.json`），新的完整推进须从真实初态单独运行。诊断记录及浮点轨迹差异详见 [JOINT-BODY-NEWTON.md](JOINT-BODY-NEWTON.md)。

早期距离目标控制：圆裙＋直条腰头接受246步，在247步由人体CCD严格停止；独立精确分数计算确认两处首次拒绝的整段欧氏间隙仍大于0.5mm，问题来自原生CCD保守坐标盒与欧氏势域不同。原生算法和物理下界保留，另用连续欧氏分离证书核验这种保守候选，任何未证路径继续拒绝。带袖上衣原32次外层控制在第一步拒绝；源弯曲GN加入P后线性预算瓶颈消除，但距离目标在固定强刚度下每步引入大量非线性工作。上述历史状态仍不是成衣。

当前加载策略明确为求解器延续法：接缝目标始终为零，`k(r)=kStart*(kFinal/kStart)^r`，默认起始 `0.001 N/m`，480步升到原 `kFinal=1/compliance`。中间帧的载荷发生变化；终点显式取原刚度，能量／梯度／原始Hv与旧零目标逐位一致。旧距离目标仍是低层 `JointObjective/Body/Garment.frame` 默认值，供固定历史对照；只有新时间推进显式选择刚度延续。能量、真实导数、稳定增量和P读取同一Frame的实际刚度与目标，报告也记录实际刚度，不能把加载比例当成已闭合的接缝比例。

五个加载阶段的联合有限差分和终点逐位对照已通过。当前圆裙＋腰头、带袖上衣各前8步完整推进通过，取消、1次Newton预算和路径证书预算仍验证物理状态逐值不变。弱载荷下的停止同时检查原绝对受力界、预条件位移指标及其真实线性残差，细节见 [JOINT-BODY-NEWTON.md](JOINT-BODY-NEWTON.md)。完整静态／重力／稳定控制尚在进行。

`numericallyStableCandidate` 只表示原标量及采样门槛达到连续24步，**没有返回 `K.Output`**。最终还需准确可见人体内外验收、完整输出绑定、App交互与导出、全目录款式/组件及目标手机验证。当前通用App路由未启用，整体3D目标未完成。

## Native117 与单 ULP 改进后的新完整运行

前述 Native111 运行的两个失败保留不变。后续原生精确展开补证已通过完整 117 项测试；求解器在原两种方向均失败且试步被舍入为零时，增加受预算约束的实际单坐标 ULP 候选。第 405 次保存内迭代和重新计算的完整外层步骤均通过原力、当前 P 修正、线性残差与完整路径检查；独立拒绝／取消控制不返回成衣，详见 [JOINT-BODY-NEWTON.md](JOINT-BODY-NEWTON.md)。

新冻结运行 `/private/tmp/TailorAssJointFSC117CoordinateFull/` 已通过同一二进制的全部负控，随后从初始裁片分别运行圆裙＋直条腰头、带袖上衣，最大 2400 步，未载入旧检查点。本轮已实际终止：圆裙接受 689 步，第 690 步线搜索拒绝（25 个已接受内部段、力无穷范数约 0.012971 N）；衬衫越过旧 405 失败点，接受 405 步，第 406 步达到 96 次 Newton 预算，力无穷范数 1.0100143e−6 N，96 段源／人体／自碰撞路径均完整通过。两款仍没有 `Validated` 或成衣输出。总进程退出 0 只表示诊断执行完成，原始失败结果与后续独立审计分别保存。

## Native123 与最新N／S的690步实际复核

在旧全程运行真实接受的689步位置和速度上，使用当前生产S的原始字节函数推进一次690物理步；只在临时源副本追加显式测试状态加载器，原S前缀与加载器分别绑定。此控制没有从初始裁片重跑，也没有使用旧未提交inner／trial作为求解初始位置。

本次25次内部更新后仍 `lineSearchFailed`，末受力约 `0.01297098717 N`；957次人体全路径检查均clear，self有504次完整clear、455次拒绝（其中2次有限精度／预算未定）。实际Session保持原689状态，未提交候选。末态源边变化约6.9754%、实际接缝间隙约0.532676微米且两类端点交叉0，不能用这些局部指标代替求解和完整路径通过。此前123对旧保存trial的证明不代表这次fresh求解已通过。

证据 `/private/tmp/TailorAssCircle690ProductionReplaySecond/delivery-manifest.json`，SHA256 `01441c7aa4c2823a24e818e3cc85d6b42eb113497f28345c69a0c582ee05a6d4`。首次测试DTO／追加加载器的并发隔离编译错误另保留，修正仅作用于测试代码。新的从初始裁片整衣driver已编译但尚未开始推进；先继续解决这次实际拒绝原因。

## Native129：正间隙补证与真实穿越的边界

三次投影多项式新增有界临界值证书，保持原零自接触下界、细分深度及运算预算。完整129项原生测试、两SDK链接和独立Fraction／Sturm复核通过；123轮实际保存的内层626项与整步1552项路径因此全部证明严格分离。证据为 `/private/tmp/TailorAssFSCCriticalIntegratedSecond/delivery-manifest.json`（SHA256 `d33a9c71dc5b324894b39e0a66473c5500c5002d1242d6b134b4a1f4330e5e9f`）和 `/private/tmp/TailorAssCriticalCertificateIndependent/delivery-manifest.json`（SHA256 `8e3a2a2a7a2fe9db1f5f01dcac5f182745c6307fb9e81e53a49446984be10709`）。

换用129库后，从同一真实accepted689位置与速度重新执行一次生产690步，17次内部更新后仍线搜索失败，状态未提交。此次产生的新trial与123轮保存trial不同：实际整步路径的EE `[60,61,1597,1598]` 在约 `t=0.495114139826` 和 `0.495116486571` 两处真实穿越。两套独立精确分数／根隔离检查分别证明根存在且交点位于两条有限边内部。局部Newton路径通过，不能证明真实整步直线通过，也不能再次通过增强分离证书放行真实交叉。

新实际失败记录在 `/private/tmp/TailorAssCircle690CriticalProductionReplay/result/replay-summary.json`；原位模式绑定与交叉证明在该目录的 `diagnostic-self/exact-actual-ee-intersection.json`，另有独立复核 `/private/tmp/TailorAssCircle690TrueCrossingIndependent/intersection-proof.json`。后续验证从真实已接受位置和速度出发的有界物理时间子步：每个子步重新形成预测位置、惯性与对应时刻载荷，逐段完成全部路径检查。优化迭代折线不能替代物理时间，旧未提交候选不能充当子步初态。

实际两半步诊断已完成：每半步 `1/480 s`，重力比例依次为 `209.5/240` 和 `210/240`。第二半严格使用第一半真实接受位置和速度，两次fresh受力分别为 `9.39652267e−9 N`、`1.66895120e−8 N`，原当前P修正与残差、完整源／人体／自接触路径和独立可见人体检查均通过。最终速度来自第二半实际位移除以其时长。根侧另用Python从实际Float64位模式独立重建10074个预测坐标及10074个速度标量，逐位匹配，时间和状态链连续。

此结果仍是带显式测试加载器的私有诊断，不能补造旧历史或返回正式成衣。交付 `/private/tmp/TailorAssCircle690PhysicalHalfStepProbeSecond/delivery-manifest.json`，SHA256 `eb139d1c042f393e637be5e1cb6359b802a081913312d97258a05e055b4cfc1d`；独立运动学复核 `/private/tmp/TailorAssPhysicalSubstepIndependent/summary.json`。正式S／R正在接入宏步原子提交、逐叶验收和失败／取消回滚；连续24个完整基础时长的稳定要求保持，完整初态运行尚未重启。

正式S／R子步实现的严格Swift编译及基础控制已通过：一次宏步最多尝试原整步和两个半步；静态装配仍无物理叶步，动态结果保存每叶真实时长、载荷、速度和路径，全部成功后才提交一次宏步。19项时序／运动学正负控制及圆裙、衬衫两份完整源的第一装配步、完整路径、freshKKT、取消与预算控制均通过。证据 `/private/tmp/TailorAssJointPhysicalSubsteps129Controls/delivery-manifest.json`，SHA256 `6890373c39a736ef4553c8b2b2b4e4762d8ccf20e9f80883abd2c37c23230aff`。此控制不包含动态第690步及第二半取消专项，它们由独立focused运行验证后才启动新的从初态整衣运行。

随后正式生产S690自动取得2个实际半步（含失败整步，共3次尝试），R逐叶fresh力、当前P、残差及全部源、人体、自接触路径通过，7种真实记录篡改均拒绝。另一个专项在第一半完全收敛并认证后触发外部取消，第二半数值尚未开始，原689公共状态和全部journal逐位不变。联合交付 `/private/tmp/TailorAssPhysicalSubstepProductionDelivery/delivery-manifest.json`，SHA256 `b8cadfe842f2efe85cc08b90a1e7ad76e17b15c6b17db43bc1decea999d6ea4b`。此时仍在重力渐入，最大速度约0.153m/s，未满足稳定验收。

唯一新的完整初态运行已启动于 `/private/tmp/TailorAssJointPhysicalSubsteps129Full`：复用上述双源controls同一冻结binary，圆裙与腰头、带袖衬衫各请求最多2400个宏步，未读取检查点。原480次静态装配、240步重力渐入和连续24个完整基础时长的稳定要求保持。运行结果必须以最终实际输出为准，启动或专项通过不代表完整成衣通过。


## Native129 有界半步的完整初态运行终态

上述唯一完整运行已实际结束，root进程54601和两个子进程均终态0；终态0表示诊断driver正常完成，不代表衣物验收通过。圆裙与腰头接受922个宏步，第923步在全重力settling阶段拒绝；带袖衬衫接受406步，第407步仍在静态收缝阶段拒绝。两款均为 `stepRejected / Newton lineSearchFailed`，`resultAccepted=false`、`outputProduced=false`。圆裙累计真实动态时长1.8416667秒，最后仍没有连续24宏步稳定。冻结binary、735份源输入与Native依赖保持；全部顺序StepReport及已接受轨迹文件齐全。封存2699份文件：`/private/tmp/TailorAssJointPhysicalSubsteps129Full/delivery-manifest.json`，SHA256 `e0477ca9c0963e8c223f09dcfd5e23d4c34a1ea4a6e5421cb00392f91c10f7c4`。记录连续性审计不冒充每条几何证书的独立重执行。

圆裙923的保存状态只读复核没有重新运行Newton。整步与第一半步的最后局部Newton路径均完整clear，但从各自真实物理起点到最后试探候选的完整运动均被同一EE `[959,960,1640,1641]` 阻挡。独立二进坐标→Fraction、Sturm根计数/160层二分和Gram线段参数证明：整步在约0.48819958665、0.48820450307，半步在约0.49170388059、0.49170947491分别存在两次严格线段内部穿越。原连续检查拒绝正确，不能通过增加正分离证书或放宽容差放行。证据在 `/private/tmp/TailorAssCircle923PathDiagnosis/exact-crossings.json`。正在用原生产私有子问题的只读诊断访问，从真实922位置/速度检查四个四分之一时间步；该诊断不提交公共Session、不生成Validated、不代表生产深度已扩大。

四个等长quarter的诊断前三段通过、最后一段拒绝，公共状态始终未提交；原失败资料保留在 `/private/tmp/TailorAssCircle923QuarterStepProbe/delivery-manifest.json`（SHA256 `716a37c5ddfd68252a54ab20c6a0d9a6e03e219023ba58523315d6ec3771c660`）。随后同一真实922状态的有界深度3诊断完整通过：9次尝试形成 `[0,2]、[2,4]、[4,6]、[6,7]、[7,8] / 8` 五段真实时间运动。每段重新计算实际惯性和载荷，并通过fresh力、当前P/残差、源/人体/自接触完整路径及独立可见人体检查；最坏力 `1.230855e-7N`、当前P修正 `2.893136e-11m`。独立逐位重构了全部真实predictor/速度/前后状态链，完整时间仍是1/240秒。最大速度约0.0752m/s，仍未满足最终稳定条件。封存836份文件，`/private/tmp/TailorAssCircle923AdaptiveDepth3Probe/delivery-manifest.json`，SHA256 `e56c3ecd2d0227bdab184673bdbbd886a2a36c40ff803717c5cfb5377a457e54`。该诊断仅调用冻结原S的私有子问题，公共Session和最终成衣能力均未提交。

生产S与R现已扩展至最多3层、8叶/15尝试；失败父区间只作诊断，所有子步完成后才原子提交宏步。完整树必须有 `2×叶数−1` 次实际尝试，真实深度由dyadic区间宽度计算；静态480次、重力240步、原质量/材料、全部原KKT/路径门槛与连续24宏步稳定要求保持。深度越界在构建工作区前拒绝；失败整步的已提交叶数报告为0。此改动正在新的冻结cohort上做长driver controls和实际S923/R逐叶验收，尚未宣称正式集成验证完成，更没有新的完整初态成衣验收。

上述正式cohort的两项检查已实际终态0：30项纯运动学控制、两源真实第一静态帧与取消／预算／越界检查通过，封存 `/private/tmp/TailorAssJointDepth3Controls/delivery-manifest.json`，SHA256 `b220beeff7626b7231276a102784cdfbb55e2405f7d08d2288c181f3e5cbab02`。当前生产S的一次实际 `advanceStep` 从真实922状态接受第923步，形成5叶/9尝试/实际深度3；R逐叶重新计算原力、当前P、全部路径，并拒绝9项真实记录篡改。另有独立逐位运动学／完整尝试树和最终可见人体验证，封存 `/private/tmp/TailorAssCircle923AdaptiveProduction/delivery-manifest.json`，SHA256 `0517429d3de87881fbe2e222280461b7595901d6382fd14cea0abba2ff757c86`。最坏力约 `1.230831e-7N`、当前P修正 `2.893135e-11m`、残差 `6.949861e-13`，仍有约0.07522m/s速度，不能生成最终成衣。该Mac单宏步专项实际约285秒，包含失败父区间的重试，不代表手机性能；后续需要优化重复试算成本。新全程运行尚未开始。

深层取消专项也已实际终态0：在真实接受并认证的 `[6,7]/8` 叶步之后触发外部取消，随后 `[7,8]/8` 数值求解未开始，公共922位置、速度、计数、上一帧和quiet窗口保持原样。测试只向冻结S插入一次已接受叶步后的observer调用，物理方程与门槛不变；独立复查了单行差异、源绑定和前后逐位状态。此observer按时间区间触发，没有另外统计取消运行中的已接受叶序号；旧producer文件名中的“fourth”仅作该区间别名，不作为序号证明。封存 `/private/tmp/TailorAssCircle923AtomicDepth3Cancellation/delivery-manifest.json`，SHA256 `c1ffe047e01ed280117bc477041a6fe497654bc92ca7652a8d0e0665abeb52d5`。以上仍是实际单宏步和回滚验证，没有生成完整成衣能力。
