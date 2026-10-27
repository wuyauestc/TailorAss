# 连续吃势接缝与整边验收

默认 PencilSkirt 的旧输出在第744步通过了当时的R数值门槛，但上侧边仍有实际裂隙：82个钉点约束最大间隙仅0.000563867mm，完整对应折线间隙却达到8.789302453mm。四种开衩参数均为0，不能把它解释为预设开衩。原记录和失败外观保留，不重写为新版通过。

`GarmentCodeSewing`现在将意图与离散策略分开：

- `ordinary`保留原源长容差及序列化；`eased`保留长侧、倍率和真实源意图，但两者均使用两侧完整源弧参节点集合，生成真正的bary约束及局部源边界区间。
- 仅`gathered`继续保留粗钉点、自由折叠节点与局部细分能力。其完整闭合尚未实现：报告明确列出未证明的接缝，不能按0间隙处理，S不能为它累计最终quiet窗口，R不能返回完整成衣资格。
- `GarmentCodeSewnInput`重新核实每个eased源节点、全部连续区间、实际相邻源面及唯一来源。源顶点、参考度量、面积质量、零固定点和全部原接缝不变，没有扩大为整面或整片碰撞豁免。

默认铅笔裙现有网格的两条eased接口由每侧5个位置增加至35个位置，总约束82→142。源参考位置、三角拓扑、可见人体和每个顶点质量均已逐位核对。这里只证明准备及质量检查，不宣称新整衣动力学已经通过。

## 吃势节点预算回退

完整primary节点列表若已在原上限内，就保持其全部位置、约束及接触元数据逐字节不变。仅当`eased`列表因额外uniform钉点而超过原每缝256段上限时，才改用完整source union；保留每个不同源节点，仅在原短侧弧长跨度确实超过hint时有界二分补点。原始source union本身超过上限，或保留源节点后仍无法满足间距，继续拒绝；没有增加256上限、合并源节点、缩短rest或修改求解门槛。`ordinary`和`gathered`不进入这个回退。

初次完整current50＋Native137准备重新执行548个不同源，结果534 ready、10个新节点预算拒绝、4个原轮廓自交；没有沿用旧544 ready结论。随后10个拒绝均通过完整源准备，534个原ready的完整计划仅经builder重建，其序列化字节全部保持一致。因此当前准备证据为**544／548**，来自明确记录的534兼容＋10实际准备，并非补丁后再重跑548次。4个原轮廓错误保留；真gathered完整闭合仍未证明，准备不等于成衣。

独立Fraction复核覆盖10例的154条连续接缝，使用精确反向源节点和完整折线最大间隙，同时核验原60mm短侧弧长间距。最多255段，仍低于原256段上限；另有真实源节点超限、稀疏区间补点、普通缝不回退、取消及非最近舍入负控。当前补丁只改变冗余uniform采样的预算回退，不改变已在进行的铅笔裙或圆裙运行所使用的合法计划。

## 完整折线指标

新的`inspect(positions:plan:)`独立于钉点采样，访问两侧**每个原始源弧参节点**；允许重复访问并如实记录`evaluatedSourceKnots`。两条折线在真实union knots之间的差是仿射函数，其范数最大值在端点，因此覆盖这些节点即可覆盖整条实际网格边界。报告的是向外舍入的最大间隙上界。

反向参数不能先把`1-f`舍入成一个新的精确knot。实现对原始Float64的数学补数使用区间`[1]−[f]`，并包住该区间所跨越的**全部实际源线段**的像；无法完成、超预算、非有限或非最近舍入环境均不发布成功报告。独立Fraction oracle从原始二进制数重建精确`1−F(f)`和全部真实union节点，检查runtime上界的有理数平方确实覆盖精确最大平方距离。

旧`Quality.maximumGapMeters/rmsGapMeters`仍表示anchor指标，旧JSON可解码，缺失的新字段不会变成完整证据。新增`continuousBoundary`单独报告已测量普通／吃势缝、未证明gathered数量及完成状态；全部为gathered时连续最大值为空。S和R仅在来源完全覆盖、没有未证明接缝且`max(anchor,continuous)<0.5mm`时才允许最终稳定／成衣资格。原受力、速度、主伸长、人体、自接触和连续运动门槛保持。

精确保留eased近邻节点还揭示了旧位置吸附造成的来源重复：两个不同normalized knot可能落在严格相同的`Location`上。现在保留每个Anchor、节点和区间，只将严格相同的`Constraint.origins`作为来源集合去重。真实失败见证为`wb_front-e0 ↔ skirt_front-e3`、constraint56：2个origins实际只有1个独立来源；所有位置、间距和方向一致。输入验证器仍拒绝外部重复来源，未放宽其校验。

## 独立整衣结果与范围

连续边修复版本另有一份从完整初态开始的默认铅笔裙实际正例：743个宏步、最终24个稳定宏步，经fresh受力、全部真实路径、完整边界及独立可见人体检查通过。全部8组源接缝的精确整边最大间隙为`1.0481083008934878e-6 m`，2片原裁片和142约束保留；旧744步、8.789mm缺口的负例没有被覆盖。该运行冻结在本次预算回退之前，后者已确认不改变这个合法primary计划。

完整交付为`/private/tmp/TailorAssContinuousEasePencilFull/delivery-manifest.json`，SHA256 `0689674ad030aba6bc47b47d164ca19a06adf4d20474ed787f3d1bafc288ca75`；[独立实际报告](Reports/2026-10-27-generic-3d/pencil-skirt-continuous/index.html)保留真实网格及OBJ。此正例仅覆盖默认参数和有限缩放标准人台，不能授予全部版型／参数、个人合体、原生App结果显示／导出或iPhone验收。

## 可复现检查

```sh
python3 Tests/NativePattern/run-continuous-ease.py \
  --output /private/tmp/TailorAssContinuousEaseCheck \
  --package-proof /private/tmp/TailorAssFSCCommonAffineIntegratedFirst
```

使用当前源逐字节匹配且已完整验证的Native包，不重新编译C++。生产持久化专项已实际通过41项分组控制和13组逐缝Fraction对照，封存于`/private/tmp/TailorAssEasedBudgetProductionPersistent/`。新增的10份完整原始纸样及参数已随fixture保存，运行不依赖旧`/tmp`源数据。测试包含原Sewing数值／ordinary／rightWrong／dart／gathered／细分／取消预算检查、完整SewnInput正反控制，以及实际Pencil全源、10份原始预算拒绝源的完整准备和eased预算边界、8mm鼓包、反向极近knot、严格来源去重、原JSON解码、RNE回调、真实局部interior/coplanar交叉仍检测等靶向控制。测试数据的旧Pencil末态只是裂隙负例，绝不生成新的`R.Validated`。

`JointContinuousSeamAudit.py`是独立的全折线Fraction复核器。`ContinuousEaseFractionCheck.py`将runtime报告与该精确oracle逐缝比较；均不重跑物理。旧ordinary／corner／gathered计划的序列化基线及旧Pencil负例均有独立hash绑定。

整边连续性修复的动力学结果必须另按完整初态运行、24个完整稳定宏步、fresh受力、全部真实路径、可见人体、完整OBJ与预览检查封存；最新款式结果见3D覆盖账本。本文不将准备／局部检查合并推导为外观已交付；完整gathered闭合、所有款式参数、个人合体、App通用入口和真机仍属于后续目标。
