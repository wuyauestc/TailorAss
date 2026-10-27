# 完整接触块预条件器专项

运行 `python3 Tests/NativePattern/run-joint-contact-preconditioner.py --output <新目录>`。
默认把完整本地 NativeClothCollision 与当前 J/P/CP 源复制到私有SwiftPM快照；
`--frozen-source` 可复验已经冻结的同结构输入，避免其它worker正在修改的依赖
混入。测试不修改N/G/P/CP或真实能量，不跑牛顿/时间步，也不声称成衣通过。

已有验证过的同字节原生库时可加 `--package-proof <原生交付目录>`：只编译App
Swift，严格核对全部原生源文件路径／字节、纠正参考夹具及实际静态库／模块头SHA，
不重新编译C++。当前纠正EE身份的原生交付目录为
`/private/tmp/TailorAssIPCOrientationIdentityIntegratedFinal`。

验证内容：

- 空contact时基P的CSC数值、product与同一factor的solve逐Double位相同。
- 完整跨片对称PSD rank-one控制、图案A→A→B→C→空→A，与显式完整矩阵方向积
  比较；每次求解独立计算真正Pz−rhs残差与正二次型。
- 两个全新的真实NativeSparseCholesky对象，其首次numeric generation都为1；
  同一CP外层token仍严格递增，所有旧token均拒绝，包含至少4次新native图案构建。
- duplicate/out-of-range IDs、矩阵维数/NaN/asym、非SPD factor、NaN rhs、400k块数、
  128MiB staged块数据、新CSC预算、开始与实际晚取消。每次update失败后旧factor
  的product和solve均不能泄漏，随后重新成功update可以恢复。
- 完整原native有袖Shirt，1732V/2710T/8显式源片/444实际sewing rows。原始输入、
  原paper JSON及原plan保持字节，paper SHA
  e923c793ce690109690eaf2ac63d726cc73d6138d554e1b8599c73e6048af5b4。
  原始输入与独立纠正参考的rest/current/triangles完全一致。当前全部560个signed
  stencils（418负项）均为跨片；数量读取 `IPCOrientationIdentity/shirt-golden.json`，
  并核对其独立能量／梯度。整体local-PSD后完整散射，
  对独立Native Evaluation.hessianProduct；不是对CP自己拼的矩阵做循环证明。
- body active小例现为24个stencils／3负项，比较完整受限cloth PSD增量；其所有
  block条目属于原source三角面9×9图案，所以新增lower entries为0。
- raw模式及未选定的ABS模式不能通过clamp-PSD Block工厂；PSD不改变原E/g，
  CP工作前后原source/body/self的Phi、gradient、rawHv保持逐值/逐位一致。

参考三角面：native归档输入保存的是用于3D面向的simulation indices。测试按
原AssemblyBuilder的91–94行反向撤销sourceClockwise造成的swap，使用未改变的
flat参考坐标恢复原CCW referenceTriangles；所有global IDs、face order、source
metrics、原simulation faces和positions不变。panel groups直接来自原生准备器
显式vertexPanelIDs/trianglePanelIDs，未从连通性或空间距离猜测归属。

边界：手写Block的“对称”并不构成PSD证明；真实调用应使用检查原Evaluation
hessianMode的工厂。synthetic rank-one块有独立解析PSD构造，负块则明确期待
factor失败。本测试不证明所有任意手写对称块是PSD，也不改变真正raw Hessian。

首轮冻结CP代码34ea012…672250、J4d8f174…27e90、Pa3dadb35…fa8b5c，是新增可选
sewing homotopy之前的distance默认版。其完整测试证据保留于
/private/tmp/TailorAssContactPreconditionerFinal；后续新Frame策略应使用新的独立
快照回归，不能改写原证据。

## EE身份修复后的实际回归

`/private/tmp/TailorAssContactPreconditionerOrientationFixed/summary.json` 记录了
当前生产J/P/CP与纠正后的91项原生库的实际专项运行，退出0、冻结源与全部原生
依赖字节保持；只重新编译Swift，没有重新编译C++。

真实Shirt保留1,732点、2,710面、8片及444行接缝，560个接触块均完整进入P，
新增2,385个下三角非零条目。四组方向的原生PSD增量相对误差最大约
`5.69e−12`，真正Pz残差最大约 `1.22e−9`，原有 `1e−9` 增量／`1e−8` 残差
门槛保持。人体控制的对应误差约 `2.15e−15`／`3.18e−14`。空接触逐位兼容、
四次图重建、旧token拒绝、无效输入／预算／真实晚取消及失败后因子不可用等
全部原有控制也通过。原能量、梯度、原始Hv在CP操作前后保持不变。

旧391／314及人体25／4属于含EE边序／距离类型身份缺陷的旧库快照，原始夹具
和旧交付证据继续保留，不再作为纠正后数值期待。新计数不是删减接触项，来自
独立官方构造器修正参考；详见 `NativeClothCollision/README.md` 的身份修复说明。
本专项仍未推进Newton或时间步，不证明完整成衣、App交互或手机性能。

源主伸长障碍PSD加入P后，同一完整CP专项另在
`/private/tmp/TailorAssContactPreconditionerSourceBarrier` 实际通过。复用纠正后的91项
原生库，只重新编译Swift；所有原图切换／残差／拒绝／取消和真实算子不变性
检查保持。源障碍代理及真实第250步的曲率对照见
[主伸长障碍预条件器](PRINCIPAL-BARRIER-PRECONDITIONER.md)。


## 当前矩阵的直接对角查询

`Workspace.diagonal(at:generation:)` 仅读取当前已完成数值更新的稀疏P矩阵。它要求有效的当前generation、合法DOF、对角CSC首项身份以及有限正值；基础图和扩展接触图分别读取各自实际存储，不构造另一种预条件器。失败或取消更新后以及旧token均不能读取。

真实接触、无接触及扩展图的首/中/末DOF对角与完整P单位向量乘积逐位相同，负DOF、越界、旧token和失败/取消后查询控制通过，证据 `/private/tmp/TailorAssContactPreconditionerDiagonal/summary.json`。该API仅减少可表示坐标提议的工作，不改变原E/g/H/P或收敛条件。
