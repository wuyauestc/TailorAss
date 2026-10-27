# NativeClothCollision

一个独立的 CPU 连续碰撞检测（CCD）、人体及布料自接触势能与稀疏分解 SwiftPM 包。它提供 vertex–face / edge–edge 保守原语、ContinuousBodyContact 人体路径 guard、SelfContactGuard 全移动自碰撞路径 guard，以及 BodyContactPotential / ClothContactPotential 端点受力。SelfContactGuard 要求独立证明初态无交叉，不能反过来作为初始化分类器。本构、Newton、人体装配与成衣质量验收由宿主联合求解器负责。

## 使用

```swift
import NativeClothCollision

// 每个端点12个Double，即4个xyz点；VF依次为vertex、triangle0、triangle1、triangle2。
let result = NativeClothCollision.vertexFace(
    start: startXYZ, end: endXYZ,
    options: .init(minimumSeparation: 0.0005,
                   maximumTime: 1, distanceTolerance: 1e-8,
                   maximumIterations: 10_000)
)
switch result.status {
case .noHit:
    // 整段[0,maximumTime]通过本次检测。
    break
case .conservativeHit:
    // 保守TOI可能是假阳性；由求解器设置严格小于TOI的步长并重新检查全部候选。
    break
case .uncertain, .invalid:
    // 不允许据此接受运动。重试、缩短候选、修正输入或明确终止。
    break
}
```

EE顺序是edgeA0、edgeA1、edgeB0、edgeB1。坐标、minimumSeparation和distanceTolerance均以米为单位。首/末点表示整段[0,1]线性运动，maximumTime限制查询时间，不能把它误作秒数。

公共C目标只暴露纯C头文件。Swift调用不需要C++ interop模式、Python、JIT、GPU或联网运行。本地SwiftPM依赖没有远程依赖；新的IPC独立目标显式禁用fast-math与FMA contraction，保留冻结参考的数值行为，不启用不安全浮点优化。

## 返回值与边界

- **invalid**：空指针/错误数组长度、NaN/Inf、越界参数、不支持的坐标量级。
- **noHit**：唯一可授权本次完整区间前进的状态，TOI为infinity。
- **conservativeHit**：原始保守算法报告可能碰撞，并达到本次请求的空间精度。TOI是保守下界；零时刻接触保留为0，绝不强行跳过。
- **uncertain**：预算/空间精度未达、无法认证非退化、线程舍入模式不支持或内部异常。不会降级成安全noHit。

maximumTime范围为(0,1]；distanceTolerance为(0,1]米；迭代预算为[1,100000]，默认10000。预算是传给上游的根查找refinement限制，`configuredIterationBudget`不是实测迭代次数，也不是精确墙钟上限。所有候选盒被排除时仍可得到noHit；存在未决候选且精度不足时必须uncertain。内存/耗时随预算和几何变化。取消在Swift调用前后检查，原生单次查询内部不抢占；调用者应在每个有界primitive之间检查取消。

仅支持IEEE754 double、FE_TONEAREST和abs(coordinate)≤1e6米。minimumSeparation须满足上游每轴坐标尺度域。Generated config拒绝fast-math，并在Clang下禁用FP contraction；没有禁用警告。对三角形的投影面积使用二次Bernstein下界，对线段的投影使用线性下界，只作输入非退化认证；不能认证的运动返回uncertain。这会保守拒绝部分并不退化的大角度运动。原始CCD的区间谓词/求根算法没有重写。

空间精度不是时间误差。TOI下界与实际接触时间可能有差，调用者不能把`achievedDistanceTolerance`当作时间误差或成衣应变质量。

## 固定来源与许可

- Tight-Inclusion **1.0.4**，commit `6f84001a790a9d3362b7c13d410037140d83fa2c`，MIT。
- Eigen **3.4.0**，使用PositionBasedDynamics commit `10a70bc146a97873dc3c8fef372f5217e010542e`中固定的原始头文件；MPL-2.0/附带宽松第三方许可。编译定义`EIGEN_MPL2_ONLY`，未修改任何Eigen头。
- spdlog **1.15.3**，commit `6fa36017cfd5731d617e1a934f0e5ea9c4445b13`，MIT，bundled fmt **11.2.0**（MIT）。上游TI配方的旧spdlog1.11/fmt9在当前Apple libc++出现弃用警告，因此仅更新日志依赖；没有改CCD算法。

`VendorManifest.json`逐文件记录原repo、固定commit、原路径、Git blob SHA-1、SHA-256及大小。只保留arm64与x86_64 iOS Simulator实编所需的头文件闭包（196个vendor源/头/许可条目）；全部第三方源/头保持上游bytes。Generated config及C/Swift包装属于本项目。完整许可证在`LICENSES/`，保留Eigen附带许可集合不代表启用GPL/LGPL模块。本包不含GarmentCode旧Warp fork的受non-commercial条款约束源码。

原始Tight-Inclusion五个.cpp全部未改；`avx.cpp`名称虽含AVX，实际编译的是其原始标量实现。包中没有x86 AVX编译参数。

## 独立验证

```sh
python3 NativeClothCollision/Scripts/run-checks.py
```

runner先复制到唯一/private/tmp快照，校验全部vendor Git blob/SHA及长期fixture，然后跑Mac SwiftPM Release测试；另编译arm64-apple-ios17.0和x86_64-apple-ios17.0-simulator的C++与Swift静态库，链接真正调用primitive和body guard公共Swift API的可执行文件，并核验Mach-O平台。构建、缓存、日志、manifest和summary.json都在输出目录，App与工程文件不改动。可以用`--output /private/tmp/一个新的目录`指定位置。

当前环境在SwiftPM默认swiftbuild后端的dSYM步骤遇到sandbox权限错误，runner使用官方保留的native后端；CLI会提示其已弃用。这是工具后端提示。源码以Swift warnings-as-errors及iOS C++ -Werror编译，未通过屏蔽代码warning来通过验证。

测试覆盖：VF/EE独立解析TOI、miss、tMax裁剪、初始接触、有限厚度、移动三角面、轴旋转/平移/尺度、共面与边界触碰、端点与中途退化、全部参数边界/非有限、舍入模式、预算不足、取消及并发独立调用。

长期fixture来自当前真实Upper失败候选的vertex1339与可见人体face15926，首/末轨迹及输入SHA固定。独立segment–triangle oracle计算TOI≈0.5108397455779176；原库保守结果约0.5108385086059570。它是被拒绝物理候选的**路径回归**，不代表上装成衣已通过。

一个2米尺度triangle、1mm separation、1e-8米请求即使100000 refinements也可能只达到约1.14e-5米；测试要求明确uncertain，并用显式20μm请求另外验证厚度TOI。真实Upper的0.5mm separation可达1e-8米。这说明精度/预算必须由求解器审慎选择；没有放宽任何现有8%应变、0.5mm接缝或穿插验收门槛。

**iOS证明是编译与最终静态链接，并未在手机运行。** 真机性能、完整候选集合、碰撞过滤与最终联合求解效果仍需后续验收。



## ContinuousBodyContact：真实人体表面的完整路径 guard

```swift
let surface = try ContinuousBodyContact.Prepared(
    bodyPositions: visibleBodyPositions,  // [SIMD3<Double>]，米
    triangleIndices: visibleBodyTriangles // [UInt32]，完整原始可见几何
)
let report = surface.guardMotion(
    previous: clothBefore,
    candidate: clothCandidate,
    clothTriangleIndices: clothTriangles,
    options: .init(minimumSeparation: 0)
)
// 宿主联合求解器仍需检查自己的能量/应变/接缝/速度等门槛。
// limited只代表路径被限制，不能标记converged或成衣通过。
let clipped = zip(clothBefore, clothCandidate).map { $0 + ($1 - $0) * report.safeTime }
```

Prepared保留传入的完整positions/triangleIndices及原索引顺序，仅构建独立的静态triangle AABB BVH。没有人体椭球代理、SDF替身、减面或秘密删除face。每个cloth triangle使用首/末共六个顶点的完整swept AABB，以separation和空间精度向外扩张/舍入；只要body triangle的AABB相交就保留候选。

每个候选triangle pair生成全部3个cloth-vertex/body-face、3个body-vertex/moving-cloth-face和9个EE组合，以真正的vertex ID、face ID及无向edge ID全局去重。不会只检查cloth vertices，也不会靠大步后的位置修复穿体。所有必要feature完成后才可以接受全局最小保守TOI：

- clear：所有候选feature均noHit，或完整broadphase已证明没有候选，safeTime=1。
- limited：全部feature完成，但存在正TOI；safeTime严格小于该TOI，默认factor=0.9，并额外取nextDown。
- blockedInitialContact：初态feature在separation/双精度数值界内，或CCD返回可能初态接触TOI=0。显式阻止，safeTime=0。
- uncertain、invalid、cancelled、budgetExceeded：整次失败，safeTime=0；不会把已处理的一部分当作完整安全证书。

**默认minimumSeparation=0仅额外防止surface穿越。它不改变原App的SDF 2.5mm、body-face 0.5mm目标。** 显式positive separation会被记录并检测初态接触；已经位于该厚度内的状态被阻止。空间tol不会换算成随意的时间epsilon。guard不改变任何source/rest/mass/pins，输出也不是收敛证书。

这是表面路径guard，不是initial containment classifier。Prepared接受开放surface；宿主仍须用真实body检查初态inside和完整物理质量。一个完全位于闭合body内且不移动的cloth component不能靠本guard获得“初态在外”的结论。初态已相交或已接触时明确阻止，不能靠guard解决穿插初始化。

预算包括：body/cloth顶点与面数、BVH节点、构建work、查询node visits、triangle pairs、去重feature数量、每primitive迭代与保守working-byte估计。默认上限为200000顶点/400000 faces、1000000 BVH nodes、100000000 build work、20000000 visits、500000 pairs、1000000 features、256MiB估计工作集。SIMD坐标按MemoryLayout真实stride计费，候选/遍历scratch及每个有界native根查找的保守scratch预留在分配/查询前检查；容器实际分配受硬数量上限约束。byte值是保守估计，不是系统实测峰值。无论哪个预算失败，都不返回截断候选的安全结果。取消在构建、遍历、候选生成与每个有界native query之间检查；单个原始CCD调用不做抢占。

完整测试现在包含16个primitive测试与16个body guard测试：240组seeded BVH候选对独立flat full scan、24组seeded刚体变换的解析TOI、VF/逆向VF/仅EE路径、全局最早TOI、跨face feature去重、初态/positive separation、全部资源预算和取消等。

真实Upper长期fixture保留完整13380点/26756面人体、1449点/2344面cloth的原previous/candidate及source SHA。它来自被拒绝的真实PD候选，并非成衣pass。guard全查10884 pairs、72825个去重features（clothVF 13758/bodyVF 13305/EE 45762），保守TOI约0.16428375244140625，safeTime约0.14785537719726563。

独立C++ oracle不链接生产BVH或Tight-Inclusion：full-scan triangle AABB、双向segment/triangle、二维coplanar overlap、对每个cloth vertex及face centroid做3方向parity rays。原候选有99个vertex sweeps、626个真实body triangle crossing pairs、99个inside vertices与189个inside centroids；限制后crossings、coplanar、inside和ambiguous均为0。独立二次多项式EE witness TOI约0.16428590278661354，大于guard保守TOI。它只证明这个候选的路径安全限制，没有证明完整联合求解器可收敛。

人体fixture来自项目可见的MakeHuman CC0 surface，完整CC0文本与固定源metadata分别保留在LICENSES/MakeHuman-CC0-LICENSE.txt及Fixtures/body-source-attribution.json。FixtureManifest逐项验SHA。没有引入Warp代码或运行时下载。


## BodyContactPotential：独立 IPC 人体接触势能

```swift
let potential = try BodyContactPotential.Prepared(
    clothRestPositions: originalPaperVerticesInMeters,
    clothTriangleIndices: originalIndependentFaces,
    body: exactVisibleBodyBVH) // ContinuousBodyContact.Prepared
let trial = try potential.evaluate(
    clothPositions: actualTrialPositions,
    parameters: .init(stiffnessPascals: 35, minimumDistanceMeters: 0.0005,
                      activationGapMeters: 0.002, hessianMode: .exact))
let Hv = try trial.hessianProduct(direction: displacement)
```

这是 IPC Toolkit v1.6.1 原始距离、屏障、mollifier及完整有符号 improved-max
surface builder 的独立 C 目标。原12叶子CPP、Eigen及上游来源文件保持逐字一致。
`IPCBodyContactVendorManifest.json` 保留首次335文件的历史来源；其中一个本地
`IPCContactBuilder.cpp` 已作下面说明的定向EE身份修复，显式新SHA与唯一历史例外
见 `IPCOrientationIdentityManifest.json`，并不声称它仍是旧wrapper字节。
255个Eigen3.4.0头文件是独立的精确跨平台闭包，旧CCD目标及其vendor manifest不变。
不含TBB/libigl运行依赖。完整MIT/MPL2及附带许可证保留；App同步新IPC MIT通知。

每个cloth面通过现有真实人体BVH获得完整 `(dmin+h)` AABB候选，再由C端
构建双向VF、EE和有符号EV/VV校正，canonical排序去重。固定人体仍保留
**非零静止面积**，body-vertex/cloth-face的cloth力也不删除。

`energyJoules`、gradient和Hessian分别是J、N、N/m。signed area项可为负，
不能把RAW或PSD模式描述成正能量保证。PSD选择先作用于整个signed local块，
再删除固定body行列；是求解器代理，不是精确Hessian。对称feature tie处不宣称
全局C2。local block的 `stencilVertexIDs` 是完整combined原ID（cloth在前/body在后），
`clothVertexIDs`、gradient、H只含原cloth自由度；没有全局dense矩阵。

候选和拓扑硬上限保持20k combined V、40k combined T、60k derived edges、
200k primary candidates、200k signed stencils。完整body BVH每cloth面查询默认最多
10000节点，工作由面数与此上限乘积界定并可取消。块缓存默认64MB，可收紧或
显式配置到256MB；callback在复制block前计费。任一预算、取消、非有限、
退化或距离不大于dmin的失败都会抛错，并丢弃**整次**E/G/blocks，永不返回部分结果。

unsigned势能不能证明outside、不能阻止已发生的穿越、不是cloth self-contact。
必须保留真实人体外部初始化、完整CBC路径guard及所有最终源、接缝、body/self
门槛。旧split求解器的2.5mm是SDF投影厚度；最终SDF穿透小于3mm是另一项诊断。
联合求解器显式使用完整三角面的0.5mm offset与2mm activation，不再后投影；
这组实验值不是材料标定。此包不自动接入App或运行成衣求解。

长期回归使用独立官方完整builder加构造器身份修正的18个canonical样例、
真实15380V/30228T拒绝cloth469姿态的861项稀疏E/G/raw与whole-local-PSD
Hessian对照，以及
离开feature tie后的FD、EE-only/BVF/负权、ABS模式、预算、取消和舍入检查。
原36个CCD/body-guard测试保持。`Scripts/run-checks.py` 同时构建新的独立C目标，
并在arm64 iOS17与x86_64 iOS17Simulator最终静态链接真正调用新API的client；
链接证明不等于在设备运行，也不构成成衣通过。

## ClothContactPotential：完整原始自由度的 IPC 自接触势能

```swift
let selfPotential = try ClothContactPotential.Prepared(
    restPositions: originalPaperVerticesInMeters,
    triangleIndices: originalIndependentFaces)
let contact = try selfPotential.evaluate(
    positions: actualTrialPositions,
    parameters: .init(stiffnessPascals: 35, minimumDistanceMeters: 0,
                      activationGapMeters: 0.0005, hessianMode: .exact))
let Hv = try contact.hessianProduct(direction: displacement)
```

所有原始节点均可移动；`LocalBlock.vertexIDs` 是完整 source 全局节点 ID，
对应 gradient 与 row-major Hessian 没有固定体裁剪。当前几何每次建立完整 cloth
BVH，面查询不排除共享节点的面。唯一邻接排除是原官方的 VF 顶点属于该面、
或 EE 共用真实端点；同一面组的非共享原语和接缝两侧独立 ID 都保留。
原始有符号 FV/EE 面积、EV/VV 负校正、合并、缓存距离类型及 mollifier 全部保留，
不额外乘自接触二分之一系数。与 body 模块共享已冻结的 IPC 叶函数/Eigen，
没有第二套 IPC 符号或新增 TBB/libigl 运行依赖，上游vendor字节不变。
两个本地builder共同使用下述定向EE身份修复。

RAW 是精确局部 Hessian；CLAMP/ABS 是整个 signed local block 的求解器代理。
它们均不保证总能量非负，feature tie 处不宣称全局 C2。单位为 J、N、N/m。
0.5mm activation、0 dmin 与35Pa是显式实验设置，不是实测面料标定。

硬预算为20k source V、40k source T、60k派生边、200k完整面候选/primary
原语/signed stencil；每面BVH访问默认10000，当前BVH构建工作上限20M、
估计驻留64MiB。块私有缓存默认64MiB，可显式配置到256MiB，复制前计费。
任一预算、取消、退化、非有限、非nearest舍入或原始距离≤dmin都会整次失败，
不返回部分E/G/blocks。`minimumCandidateDistanceMeters`只代表实际候选，不能
冒充全局最小距。

长期专项包括：独立官方完整 builder 加身份修正后的20控制 E/G/RAW/whole-local-PSD
稀疏对照（共享1V/共享边的非相邻VF确有力、distinct sewn IDs50µm确有力）、
4个全moving away-tie FD、完整1732V/2710T有袖Shirt的560 signed stencils
（418负项）、不手改坐标的完整圆裙与r237数学状态 inactive 控制、矩阵自由Hv、
刚体协变、并发只读、取消和全部预算。原官方参考源码与pinned source manifest
位于 `Tests/Oracles/IPCClothFullReference.cpp`、`IPCFullSourceManifest.json`；
`Scripts/build-ipc-cloth-full-reference.py` 可复用已有完整官方 Ninja/TBB 研究构建
重建独立参考，日常回归只用已封存goldens，不依赖此研究环境。

势能评估是 endpoint force 模块，不是全路径安全证书或整衣求解器。调用者仍须
保持严格正距初态、完整 self CCD、真实人体外部初始化/CBC及所有最终源/接缝/
body/self/收敛门槛。静态 inactive 不能用于禁用以后动态 self force。


## 定向EE身份修复与独立参考

v1.6.1原完整builder的EE键把两条边视作无序，但固定`dtype`仍按有序边解释。
反向提交的负EEEV校正可因此与另一物理距离函数错误合并。完整Circle218真实
两状态仅相差6.3e−15m，旧官方builder和旧移植都产生3.8244e−7J有限能量跳变；
这不是可通过调参数或放宽Armijo解决的问题。

两个本地wrapper现同时规范化键与实际stored stencil：交换边序时dtype交换
1↔2、4↔6、5↔7，其余对称类型保持。原始signed面积、候选、mollifier、距离叶、
物理屏障、固定人体消元及全部自由度不变。不修改任何上游vendor源码。

新参考不是由生产端口自己生成：在固定官方完整builder中只给三个EE构造器
应用`Tests/Oracles/OrientationIdentityCorrection.patch`，再与不合并EE、逐个保留
原方向signed项的另一完整官方builder独立对照E/G/raw H；两者相符至舍入误差。
PSD是合并后整个signed局部块的非线性投影，使用纠正后的合并参考单独核对，
不拿未合并的PSD作为同一个代理。真实Circle218跳变降至约1.5e−17J，方向FD、
raw Hv、边/顶点重编号、固定body只取cloth导数均有专项。

旧`IPCBodyContact`/`IPCClothContact`原goldens、旧87项集成证明及历史manifest
原样保留；它们包含同一个上游身份缺陷，不能作为修正后的数值期待。新证据独立
位于`Fixtures/IPCOrientationIdentity`，manifest绑定参考修正、全部原输入SHA与
当前oracle文件SHA。成衣是否可用仍须完整生成与最终validator通过，修复接触
能量不等于已通过完整3D验收。

## SelfContactGuard：零间距与双方运动的欧氏补证

默认物理最小间距仍为0，native distanceTolerance仍为1e−8m、安全系数仍为0.9。
原全源三角面／边的整区间非退化证书、primitive-ID邻接排除、初态无交叉前提、
32ulp初始接触拒绝均保持。独立接缝节点没有任何新豁免。

Tight-Inclusion的保守坐标盒或精度预算可在实际整段仍分离时返回hit／unknown。
仅当原native已经证明primitive域，且返回`conservativeHit/none`或
`uncertain/precisionOrBudget`时，SelfGuard才调用已有`FeatureSeparationCertificate`。
证书必须证明**同一四点完整[0,1]路径**的真实闭集欧氏距离严格大于原物理间距，
才能跳过这一候选并继续检查全部后续features。不是只看端点，也不修改tol。
`uncertainGeometry`、无效输入、非nearest舍入等不能被距离证书覆盖；证书未完成、
取消或预算失败继续拒绝整次请求。旧初态已有穿插反例仍说明此guard不能当初始化分类器。

该投影证书同样适用于dmin0和双方运动：任意时刻两个特征上的点都是其顶点的
凸组合，固定方向上的差是所有顶点对投影的凸组合；每一对沿时间线性变化。
在每个有界子区间对全部顶点对端点作外舍入严格下界，即覆盖所有时间与特征位置。
数值最近点只提议方向，不参与安全断言。没有找到方向时返回notCertified。

默认每完整query的额外节点上限为262144，单feature沿用已有depth12／最多8191节点。
统计明确报告`euclideanCertificateAttempts`、`euclideanCertifiedFeatures`、
`euclideanCertificateNodes`及`euclideanCertifiedAfterPrecisionLimit`。候选列表／
native query之前另预留与BodyGuard相同的1MiB临时证书工作估计，原256MiB总上限
不变；1MiB是保守计费，不是实际分配或RSS测量。原三角／边域节点预算单独保持。

真实Circle387和Shirt343原始失败均为native `precisionOrBudget`，并非32ulp分支。
同一库和同一四点端点不改，独立exact-Fraction验证给出整段严格距离下界约
0.780354µm与2.229189µm。补证后完整query分别继续检查702／1989个features，
各只需一个补证节点。完整原始输入、旧native报告及新回归独立保存在
`Fixtures/SelfEuclideanSupplement`；`Tests/Oracles/self_feature_separation_fraction.py`
逐叶独立验证Float64位型哈希、全[0,1]覆盖、投影／范数／距离上下界。

这是路径证书改进，不是接触力、材料、成衣平衡或最终质量门槛的改变。两条实际
局部路径通过也不等于整个Newton步或整衣已验收。原100项冻结证明不覆写，
当前Swift模块必须使用包含这些新增回归和双SDK最终链接的新证明。
