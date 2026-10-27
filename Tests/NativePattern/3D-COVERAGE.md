# 全部 3D 功能覆盖与验收账本

> 首次审查于2026-10-26，当前概况更新至2026-10-27；历史运行按各自冻结证据保留。目标仍为“完成全部 3D 功能”，**整体未完成**。

范围以当前 2D 生成器与参数目录为准：12 款主版型、122 项设计参数、26 项人体输入、7 项派生公式，以及已有领袖组件和款式组合。原生离线实现可采用适合 iOS 的算法；不再沿用旧 Unity 固定 T 恤方案。

本次审查未重新运行全部数值套件。下表严格区分 App 已接入、数值快照、仅平面/约束基础与尚未实现。数据明细、全部参数逐项映射及后续进展保存在 [3D-COVERAGE.json](3D-COVERAGE.json)。

## 当前交付边界

生产联立链条现已包含真实膜、主伸长障碍、源铰链弯曲、完整接缝、人体与布片自接触，并检查完整连续运动。当前原生库129项测试与两平台最终静态客户端链接通过。动态时间步现已支持最多三层有界二分，最多8叶/15次尝试；每叶重新计算惯性、载荷及速度，全部接受后才提交宏步。前一版半步机制的完整初态运行停在圆裙923、衬衫407步。随后深度三及已提交分段复用已通过真实923→924专项和失败／取消原子回滚；57项数据控制和两款真实静态首步的整合通过。跨运行481的逐位一致断言仍失败，同policy重复也有约1e−15m位置差，全部原物理门槛通过，该限制单列记录。新版本完整初态运行已结束：圆裙接受1130步，第1131步更新方向搜索失败；衬衫接受412步，第413步耗尽Newton预算。两款均未通过成衣验收，失败候选已保留供诊断。该两款历史运行没有通过最终验收；当前另有2个默认腰头组件及2款默认完整源裙装通过通用链R的最终24宏步稳定及独立可见人体验收；其中铅笔裙仍有约8.77mm的吃势侧边裂隙待修，数值通过不代表接缝外观已交付，详见下方最新输出。详见 [JOINT-GARMENT.md](JOINT-GARMENT.md)、[分段复用验证](JOINT-PHYSICAL-SEED-FOREST-DESIGN.md)和[真实种子专项](JOINT-SEED-FOREST.md)。

完整目录的当前准备证据为544／548个不同源：连续吃势版本先实际执行全部548源，得到534 ready、10个冗余uniform节点预算拒绝及4个原轮廓自交；吃势预算回退随后使10例通过完整准备，534个原ready完整计划经builder重建逐字节不变。没有在补丁后无理由再跑全部548次，也没有沿用旧Native111结果作为新版证明。其余4个原轮廓错误保持拒绝；准备通过不代表整衣通过。旧App812证据保持；新App817已完成iOS设备及模拟器两架构的完整Release构建、安装和启动，实际17文件SHA一致。该App817界面读取曾中断，历史记录保留；后续App826有限界面验证见下方，不能据此补齐旧快照未包含的物理验证。拟合人体工厂与完整静态表面验证现已接入显式选择的计算路径，默认／女性两体×圆裙／衬衫4组实际装配、32项否定控制及2款真实静态首步复核通过；旧12组完整状态字节对照、16摆臂案例和134控制保持。输入来源、完整人体表面、Q查询、避让与显示网格一致，旧SDF不能进入拟合分支；App默认路线未更改，26项尺寸未全部独立拟合，拟合人体衬衫另一次完整初态运行接受400步，在第401步耗尽Newton预算；该运行使用独立冻结版本，终态独立审查已完成，拟合人体整衣动态仍未验收。详见[拟合人体接入](FITTED-BODY-INTEGRATION-DESIGN.md)。

参考摆臂人台已通过16组完整准备、134项负控和旧状态兼容检查。同一份经过独立资源重放授权的网格用于避让、碰撞和展示；该能力没有补齐26项尺寸的独立人体拟合，也没有完成摆臂状态的整衣动力学。后台流程、通用页面状态和完整原生JSON输入已有独立检查；实验入口现已接入，App826仅完成实际进度／取消／重启的有限界面检查，尚无通用成衣显示或导出验收。详见 [BODY-RIG-POSE.md](BODY-RIG-POSE.md)、[JOINT-WORKFLOW.md](JOINT-WORKFLOW.md)和 [JOINT-DRAPE-VIEW.md](JOINT-DRAPE-VIEW.md)。

以下进展、旧运行指标和首次审查表按各自冻结源码解释；后续通过的局部证明不会覆盖旧失败记录。最新结果以JSON账本的`subsequentProgress`与对应冻结交付为准。官方最终模拟网格尚未取得，当前没有GarmentCode或Design2GarmentCode的三维数值一致性结论。

618 个目录 case 的 548 个不同源已实际执行完整准备：原快照 536 个准备通过、8 个分层接口拒绝、4 个原轮廓自交。随后分层裙真实下摆修正通过 24 组独立上游对照；8 个更新源重新准备，6 个通过、2 个在刚体布片避让阶段达到原有预算。按源引用累计 542 个不同源、612 个 case 有准备证据，来自两个明确区分的编译版本，尚无本批整衣动力学或 App 验收。四个轮廓自交已由原曲线解析求交及未改上游同参数生成独立确认，不能通过放宽网格校验把它们变成可裁剪纸样。详见 [LEVELS-HEM.md](LEVELS-HEM.md)及 JSON 账本。

后续刚体布片避让加入保守 BVH，原窄相位、移动顺序及预算保持；8 个更新源均通过准备，211 个旧案例的完整准备状态与原计划保持一致。此前Native111统一快照实际重新执行全部 548 个不同源（复用旧结果为 0），得到 544 个 ready／4 个已知原轮廓自交，对应 614／4 个目录 case；后续独立检查已完成：544 个输入的同源裁片、面积质量、零固定点、完整接缝与初始静态几何全部通过，4,854,164 个人体外部样本及全部独立 VF／EE 距离已检查。20 个对称轴退化样本用两条新增精确有理射线消歧，未将 unknown 当作 outside。冻结批次为 `/private/tmp/TailorAssUnifiedCurrent548Prepare111-s0l187gz/`，交付 SHA256 `4d52079af68cfb7af20a76ecbaf7ea4e521d7cfc5b40f40f47f4b5d80edce319`，使用 App788 模型和 Native111。此批未执行 Newton 或物理推进，不能把初态通过当成成衣通过。

二维入口现已提前提示可确认的原轮廓交叉，修正参数后同款式可继续生成；导入异常源可保留 JSON，但不能打印、加工缝份或进入 3D。半圆扫向在显示／打印／网格链中的重复 helper 已统一修复。两平台 App Release 构建及 Device Hub 的真实导入／生成／原字节导出检查通过，详见 [SOURCE-CONTOUR-DIAGNOSTICS.md](SOURCE-CONTOUR-DIAGNOSTICS.md)。上述原字节保存证据绑定 Native111／App788。后续 Native117／App795 与单 ULP 求解修正另已完成两平台 Release 构建和实装界面验证，修复长警告挤出布局，确认普通纸样交互保持正常。新的两款整衣运行已从初始裁片执行至终态：圆裙 689／690、衬衫 405／406 接受／拒绝；均无最终验收成衣，具体失败正在诊断。

最新局部修复已更新：原生碰撞模块123项完整测试、独立精确分数检查和两平台静态链接通过；此前圆裙690步保存候选的626条局部特征与1,552条整帧特征均已确认安全，但新的完整690步与从初态整衣推进仍须另验。衬衫求解增加正常候选与有界单ULP候选的严格能量比较，生产版本和最终123包的五项新边界控制及原Newton控制通过。所有原能量、路径与最终质量门槛保持，目前仍没有新的通用成衣验收输出。见 [Newton修复说明](JOINT-BODY-NEWTON.md)和[实际轨迹绑定](JOINT-TRAJECTORY-BINDING.md)。

## 本轮后续进展

App826已在Device Hub的iPhone 17／iOS 27模拟器实装并启动，17份安装包文件与冻结构建逐字节一致；安装前后、启动前的Documents／Application Support／Preferences内容保持。实际新页面读到“2片原裁片／2组配对接缝”和真实缝合步数，点击取消后可重新开始，用户随后另一次运行继续。证据在`/private/tmp/TailorAssApp826UISmoke/installed-binding.json`和`ui-observations.json`。尚未观察到完整成衣结果或验证App导出，也不是物理iPhone测试；此安装快照不含后续吃势预算回退。

默认铅笔裙连续边版本的新独立结果已封存：从完整初态743步通过最终24宏步，8组源缝的精确整边最大间隙`1.0481083008934878e-6m`，不再是旧钉点指标替代整条边。2片原裁片、142实际约束、零固定点及原源质量保持，标准人台个人合体未验证。交付`/private/tmp/TailorAssContinuousEasePencilFull/delivery-manifest.json`（`0689674ad030aba6bc47b47d164ca19a06adf4d20474ed787f3d1bafc288ca75`），[实际报告](Reports/2026-10-27-generic-3d/pencil-skirt-continuous/index.html)。旧744步开口负例仍保留，不能以该新默认单例覆盖全部参数或App显示／导出。

当前吃势预算回退已提升生产，精确源码SHA为`467188f1d7f16e4bafe9ce42f5b23a909f024662d6e163f9d6b1d7b4afac992a`。仅primary超过原256段且意图为eased时保留完整source union并对过长区间补点；普通／真抽褶与所有合法primary计划不变。534个旧ready完整计划字节兼容＋10个真实完整准备，构成当前544／548准备证据；4个原轮廓错误不变。10例154条整边的精确有理数上界／间距检查及source本身超预算拒绝通过；没有Newton、整衣或App运行。原548新准备封存`b8e338c590e53e07b368aafea5fbbbc47d423f02634aad94ad35a0009aeed65c`，预算回退隔离交付`ccad2a6f7ae55bff909121508e3043b44e0c1aa718fce2b545d7212c29f60a91`；见[连续吃势说明](CONTINUOUS-EASE.md)。504个准备源拥有完整ordinary/eased闭合模型，40个仍含未证明的真gathered，不可据ready数量授予完整成衣资格。

连续吃势缝已提升生产：保持原裁片、参考面积质量和独立自由度，普通／吃势缝使用完整边界对应，真抽褶继续保留原自由节点。S逐叶与R最终验收现检查完整折线边界，旧只量钉点的质量记录不能据此获新验收；反向参数使用保守区间覆盖原始节点。原Sewing全套、SewnInput 3正向／38否定、25项新控制及3组逐缝精确有理数对照通过；原普通／角点／抽褶计划JSON不变，近邻节点严格重复Origin仅按集合去重且不删Anchor。交付`/private/tmp/TailorAssContinuousEaseDelivery/delivery-manifest.json`（`41875c28db1cd7bfe062a4a565e182fa673487baa6027b50b15bdf29a68b9246`）。新版默认铅笔裙另有743步完整验收正例见上文；圆裙＋腰头仍按独立运行记录解释，不因局部控制通过而授予完整成衣结论。

共同尺度法向补充已进入生产碰撞模块：只在旧提议无法证明安全时提供第二个方向，仍逐一证明整个运动区间内全部真实特征对的分离；没有扩大时间细分、精度或工作预算。137项Mac测试、两SDK最终客户端链接与独立精确有理数检查通过。封存`/private/tmp/TailorAssFSCCommonAffineIntegratedFirst/delivery-manifest.json`（`79d109122c17257645a7560483977bb19ea9f0943afe7b27908c0c6c9f53cae7`），root另复核186份证据及546份源文件哈希。保存的圆裙路径通过不等于新的实际1131宏步或整衣通过。

整体交付成熟度仍约50%，为面向全部3D功能的主观工程估计，不是测试通过率或款式通过比例。全部款式／参数范围、原生App通用路线、真机性能和个人合体仍未完成。

- **默认版型初态批次已结束**：此前11款冻结批次加上独立StraightWB，12款默认版型均已有完整运行至终止的记录。旧R返回StraightWB、FittedWB、Skirt2、PencilSkirt、SkirtLevels共5份数值输出；不是5款完整交付。新的独立有理数整边审计覆盖全部原始源接缝和真实分段折线，前3份通过0.5 mm闭合阈值，PencilSkirt／SkirtLevels分别因8.789302453／8.224284168 mm开口拒绝。反向源参数按精确`1−Fraction(f)`处理，未将舍入后的反向节点作为原曲线；8 mm中间鼓包、异节点同曲线和反向舍入控制通过。全边审计V2为`/private/tmp/TailorAssFullBoundaryAuditsV2/delivery-manifest.json`（`a022dee5149df21ac84973192426da72e88d71a1bb161d4462c2285041eb11cb`）。

- 剩余默认Pants／FittedShirt／Shirt／SkirtManyPanels／GodetSkirt／SkirtCircle／AsymmSkirtCircle分别在第171／176／160／183／251／751／188步耗尽Newton预算，原公开状态保留在前一步，没有最终输出。原11款批次进程已返回0；这只表示驱动完成，不能当作款式通过。终止记录、源纸样、最后公开状态及旧R输出的关联复核见`/private/tmp/TailorAssDefaultStylesTerminalReviewV1/delivery-manifest.json`（`0e03a4520367b2915e3ddeb3588f795c37fbb8c5734c198eb9bf2f43d601173f`）；没有重新执行全部力或运动证明。以下较早“四份输出”记录保持原审查时间和范围。


- 当前通用求解器共有4份R数值最终输出：默认独立StraightWB与FittedWB两个组件（各743步），以及默认完整源双片裙Skirt2（1358步）和铅笔裙PencilSkirt（744步）。四者均从完整初始裁片开始、零固定点，经R最终24宏步受力／完整路径／可见人体检查返回输出，未调用旧专用后端；不计作完整上衣或衣服组合通过。StraightWB原交付`d9ca0b6b…98e8`和Skirt2单例交付`bb75e8ea…1c21aa52`保留。双片裙源边最大变化6.568%、实际钉点间隙0.000531mm、速度0.006741m/s，裙口位于髋部，个人合体未验证。四份[实际离线报告](Reports/2026-10-27-generic-3d/pencil-skirt/index.html)均保留真实布料与人体、2D纸样和原始OBJ；不代表全部参数、原生App通用入口或真机验收。

- 默认铅笔裙单例审计核对744个连续接受步骤、2260段真实静态轨迹、264个物理叶，最后24宏步／24叶全部fresh受力及三类完整路径通过；1031点／1802面、4组后片省道＋4组前后侧缝、82个实际bary约束、零固定点、0.105266kg源质量均保留。末态源边最大变化6.6654%、钉点间隙0.000563867mm、速度0.000245065m/s，5664个人体样本全在体外，含人体OBJ有14411点／28558面。单例交付`5c94c6115bbbc4b12e7e6fd272c3397d5a851a663605cff3c3bd6f8a5493e6db`，只封存该案例，没有封存或重跑live款式批次。

- **铅笔裙的整边视觉缝合仍有缺口**：默认四种slit均为0、装饰切口为空；原上部两组侧接口因源长差约5.1411%被声明为eased，但现计划与gathered一样仅放置粗钉点，留下每侧9个自由边节点。精确有理数核对这些节点到完整对侧折线的最近距离，最远为8.77249mm和8.66073mm；同一归一化弧参的完整分段折线最大间隙为8.78930mm和8.68039mm。该完整折线指标与现有有限钉点指标不同，不能用后者的亚微米结果覆盖侧边裂隙。三视图可见上部细线，已记录`visualSeamReviewPending=true`；不能称为预设开衩或外观完整可交付。下一步需区分连续吃势缝与抽褶自由节点，并增加整边质量检查，原源几何和全部受力／连续碰撞门槛保持。

- 四层分段已完成真实1131宏步尝试，但在第14次求解的`[9,10]/16`区间失败，1132未执行，默认仍为三层。7次预算耗尽及真实前缀后取消均保持公开状态／分区／帧／稳定窗口不变；异步取消竞争的12项控制通过。源和位模式回退审查见`/private/tmp/TailorAssPhysicalResolutionOutcomeAudit/delivery-manifest.json`（`e73c2c14fda5f0198a24ca48e8e01e0ecad62f15da527c59a9ed330f378a028d`）。该腰头＋圆裙组合仍未通过；当前完整源下装的数值正向输出为上文默认Skirt2及PencilSkirt，后者仍有明确的视觉接缝问题。

- 衬衫413的主伸长障碍能量增量修复已完成：真实412→413回放37次Newton通过，原96次预算、受力、完整路径及最终质量门槛保持。最终D为`efd674f4…bf91cfe`，长期测试、独立高精度核对及两个SDK真实链接通过；交付`f0ace66d…85c2e92`。当前50模型整合的57项数据控制与两款真实首步亦通过（`70b224f7…ca713`），同一冻结二进制从初始裁片重跑后接受416步，在417步耗尽预算（终态交付`90c1acf9…acbd3`）；原413停止点已通过，仍无最终成衣。
- 圆裙1131的两次失败候选已独立重查：内部Newton路径安全，但实际时间步起点到候选的路径均在布边`[958,959,1640,1641]`间出现两次真实内部交叉。精确有理数／Sturm证明支持原碰撞拒绝，交付`b4ff8ef9…72a4ca`。另以原45模型和真实已接受前缀为起点，将失败区间`[1,2]/8`细分为`[2,3]/16`及`[3,4]/16`，两次实际求解及fresh受力／P／全部路径／可见人体检查通过；速度仍约0.0467m/s，未达最终稳定。独立位模式运动学复核及交付`187f8365…5de6af`只证明该局部区间，不是完整宏步或成衣。
- 拟合人体衬衫的完整初态运行终态审查已完成：826运行文件、741源文件和14项原生依赖绑定保持；400个已接受静态帧包含3132条实际配置段，第401步耗尽预算，未提交失败候选，未生成最终输出。交付`7a646ca3…28c97`；该失败的局部诊断不能替代完整受力复核。

- 局部源边细分、真实抽褶接缝重建及完整源输入校验已通过；通用装配器重建两种腰头保持初态、源度量、质量、人体及接缝计划一致，实际物理门槛通过。
- 输出保留每片源顶点与三角面分组，实际 OBJ 分组和 JSON 往返已验证；损坏的可选分组不能造成丢面或越界。旧版八组圆裙／双片裙 OBJ 逐字节兼容。
- 原始三维摆放模块及 14 个真实裁片验证完成；480 片官方上装的动态平移公式对照误差为零。详见[摆放映射与限制](3D-PLACEMENT.md)。这些证明不等于已完成衣服缝合。
- 原生下装摆放已映射八类下装及实际裤口、插片、层裙和可选腰头，两人体型 374 个官方源裁片对照通过，完整源哈希、旋转与法向保持。详见 [LOWER-PLACEMENT.md](LOWER-PLACEMENT.md)。这是分离裁片的构造位置，尚未接入 App 或证明整衣收敛。
- 下装摆放对照发现的两处二维分支已修复：无上衣的裤装／腰头统一读取 `pants.rise`；插片裙使用铅笔裙基础时按上游 `slit=False` 抑制四种开衩。25 组独立官方完整几何、134 片摆放、原始设计来源和单独铅笔裙开衩均通过；原 356 组及打印等联合验收、修后 374 片矩阵通过。
- 27 组源网格覆盖全部 12 款主版型、领袖和袖裤口组件、1.95 展开量圆裙及完整组合，共 174 片原始裁片、64,360 个三角面通过独立源面积、边长与预算检查。这是平面网格覆盖，不能代替整衣三维验收。
- 腰头＋圆裙的三组完整源装配通过。最新四片六缝严格运行保留原质量与固定点，人体交叉、自交、独立体内顶点与面中心均为零，但源边最大应变 27.393%、实际缝合间隙 0.591342 mm、末态速度 0.04431 m/s，整体仍不合格，尚未接入 App。
- 多片真实缝角的接触等价关系、虚拟缝合点的同源人体接触、按源裁片限制的接触带及源路径上界分别通过局部测试。完整集成仍不达标；不能将局部测试合并推导为成衣已经收敛。实际末态单步接触复查未重新拉开腰头侧缝，当前没有继续扩大接触豁免的证据。
- 后续静态阶段归因确认：源应变修正后，逐条缝合会留下微小角点错位，再形成三处真实面内穿插；高精度独立计算证实不能豁免。新增 `SewnPointBlock` 在收缝完成后按原质量联立处理共享点，保留独立自由度和原顺应度，解析／冗余／固定点／旋转／预算／取消及真实 69 行独立线性对照均通过。显式控制下的现有腰头物理通过，旧默认几何与 OBJ 保持一致。
- 较早生产快照的完整联立缝合组合对照：间隙 0.475703 mm、速度 0.00631664 m/s、人体交叉／自交／体内采样均为零，但源边应变 32.4208%，仍不合格。延长静态装配的隔离对照也未通过，不作为默认方案；不能因部分指标通过而开放为成衣功能。
- 上装四片源装配已完成六组构造检查，但严格三维运行仍因局部源边应变和速度不合格而拒绝。袖领、裤装、其他裙型和完整组合仍按下列全范围推进。整体目标没有完成。

## 更新的构造验证（不代表物理验收）

- 上装同源重放已通过 108 组、868 片，含衣身、袖领、袖口及不对称组件；逆袖窿无交点分支已修复，原有 107 套源哈希保持，另有 12 组官方专项对照。见 [UPPER-PLACEMENT.md](UPPER-PLACEMENT.md)、[INVERSE-SLEEVE.md](INVERSE-SLEEVE.md)。
- 完整组件相对摆放通过 160 套、1,116 片对照；合体上衣搭配三类喇叭裙的腰位规则修复通过 48 组完整纸样与摆放对照。保留原始设计和全部裁片，未做动力学等价声明。
- 同源腰头＋圆裙的刚体去嵌入控制将初态人体交叉 226→0、体内顶点/面中心 193/351→0/0；源边最大初态应变约 2.2e−14、质量、独立自由度及零固定点保持。实际初始接缝间隙为 594.825 mm，仍未收缝。此证明只覆盖该初始化控制，不代表所有体型或组件均无初态冲突。
- 本地原生连续碰撞包已建立真实 Swift→C→C++ 链路，iOS17 arm64、Simulator x86_64 静态链接通过。连续人体运动检查按完整特征和预算拒绝未确认的路径；它不能替代布片自接触或最终质量验收。新增 App 适配与可选求解接入仍在独立验证，现有 App 入口尚未启用。

以下款式表保留首次审查的 App/物理范围；其中早期“初始摆放缺失”的描述由上述构造验证更新，整衣物理与 App 接入缺口依旧存在。

## 最新严格控制与修复

- 原唯一袖片准备失败已修复；完整原生装配211/211通过。源边界恢复仅在原细化真实失败后执行一次，同源边界更密采样，原目标、曲线误差和网格预算保持；189份旧完整网格、233份JSON逐字节相同。
- 211套刚体人体间隙初态的人体交叉、体内顶点/面中心与歧义均为零；旧人体单独模式中14套真实互穿或共面重叠已由显式联合初始化修复，197套原状态保持，全部缝合计划按最终位置重建。联合模式211套通过两类交叉检查；这仍不等于所有非邻接特征均有严格正距离，接缝中心重合的独立裁片正在进一步检查。详见 [RIGID-CLOTH-CLEARANCE.md](RIGID-CLOTH-CLEARANCE.md)。
- 新完整物理控制实际完成469帧，在候选470帧被连续运动检查拒绝，未返回成衣。已接受的469帧源边最大应变112.7103%、布片自交3处，仍不合格。请求2,400帧不等于完成2,400帧，修正运行说明另有独立JSON，不改写原始快照。
- 新源三角膜模块已通过能量/梯度/精确Hessian、主伸长障碍势与路径步长、独立LAPACK SVD及真实拒绝资料检查。第60帧虽然源边变化约5%，最大主伸长已达1.1834，说明仅按边限不能充分约束面内形变。见 [MEMBRANE.md](MEMBRANE.md)。该能量尚未成为App整衣求解后端。
- 连续三角非退化证书增加有界、向外舍入的范数后备，保留全部真实塌缩和未证明路径拒绝；36项原生测试、精确有理数对照及两平台静态最终客户端链接通过。完整470路径仍被另一原边证书拒绝，没有被当作新物理通过。
- 包含源铰链弯曲能量的完整App快照，iOS和Simulator Release均构建通过（326份精确输入；后新增的稳定增量与联立能量另有独立编译测试，尚未安装或运行真机）。构建不能证明成衣收敛，整体目标仍未完成。

- 源内部铰链弯曲能量已实现，真实纸样的4,948个铰链通过独立能量、梯度与精确Hessian核验；近似PSD模式单独标示，不在接缝之间增加假铰链。见 [HINGE-BENDING.md](HINGE-BENDING.md)。尚未加入整衣动力学。
- 联立求解的第二步曾因普通总能量相减丢失极小变化而停滞，实际Double坐标的80/100位对照确认原因。稳定增量公式通过25个真实候选；从原始初态运行的前16步通过两项严格KKT、源形变及碰撞检查。主伸长障碍尚未激活，人体力及弯曲尚未加入；实际接缝仍约0.575m，不能称为缝好成衣。
- 同一第16步仅更新预条件器中的当前源方向，实际Φ、梯度与Hessian保持；Mac控制耗时7.307→0.664秒，全部CG真收敛。这不是手机性能或完整求解耗时。

- 稳定弹性增量已提升为生产模块，保留实际存储坐标及域／分支／精度失败，25个真实Newton候选和4个完整源激活障碍＋弯曲样例通过；只声明Double估计，不声明普遍精确符号。惯性、膜、障碍、弯曲与全部真实接缝也已汇总为单一生产目标，联合E/g/精确Hv及稳定增量通过。详见 [ELASTIC-ENERGY-DELTA.md](ELASTIC-ENERGY-DELTA.md)、[JOINT-OBJECTIVE.md](JOINT-OBJECTIVE.md)。这些模块尚未包含人体／布片接触力或完整时间步求解器。

## 生产联立链条的最新接入

- 新显式正间距初始化已对完整211套通过独立VF/EE、人体与体内检查；633个旧三模式签名保持。跨片实际最小约50.001µm，同片非邻接最小约0.264mm，精确零／10nm内原语均为零。两套翻领使用保守的实际源足迹支持细化，原位移与工作上限未扩大。见 [POSITIVE-CLEARANCE.md](POSITIVE-CLEARANCE.md)。
- 完整源封装已桥接到生产联立能量，保留源SHA、人体、全部真实缝合及SI面积质量。原第63步整段形变证书过松已由同一路径有限分段解决，不放宽主伸长域。见 [MEMBRANE-PATH.md](MEMBRANE-PATH.md)。
- 原无人体力控制推进至236，第237步首次完整人体势激活便停止；没有用缺力目标盲目续跑。完整signed人体势已提升生产Package，原完整builder独立对照、Mac45测试与两平台59项编译链接检查通过。
- 新生产Newton与真实人体力的第237步数学子问题通过18次Newton及全部CG真收敛，梯度约8.81e−8N、源边变化约1.42%、末态布片交叉0。该控制关闭弯曲／重力，尚无生产self力或self连续路径，不是整衣物理接受。见 [JOINT-BODY-NEWTON.md](JOINT-BODY-NEWTON.md)。
- 上述新链条尚未接入App通用成衣入口；全款式完整收缝／重力／持续稳定、真机运行及完整对照仍待完成。

## 人台参考测量

新增同源参考测量模块，保留实际网格、26＋7 参数、几何／参数 SHA 和所有截面环。用明确的轴点严格选择唯一包含环，得到可见高度、腰／臀参考周长和纯垂直胸部参考截面；边界、不确定或多个包含环均不给可用测量。默认／女性共 6 个实际截面及解析、取消、预算、非正目标控制通过独立复查；严格 Mac 编译和 iOS 分支 typecheck 通过。尚未建立全部解剖测量定义，也未做尺寸拟合或接入 App。详见 [BODY-MEASUREMENTS.md](BODY-MEASUREMENTS.md)。

## 当前 App 路由

### 后续完整接触推进验证

- 完整 signed 自接触势和连续 self 检查已加入生产链条，Package 当前72项实际测试及两平台最终 Swift 静态客户端链接通过。源码弹性缓存绑定同源、实际位置和材料，联合原始 Hv 与无缓存公式逐位一致；这些检查没有改变物理门槛。
- 新整衣目标的同一场景同时激活膜障碍、非零弯曲、缝合、人体和自接触，联合导数通过；实际带袖上衣保留8片、1,732个独立点、444行接缝，完整自接触与原 builder 对照。见 [JOINT-GARMENT.md](JOINT-GARMENT.md)。
- 完整时间推进已从正间距初态启用：圆裙＋腰头前8步接受但仍未收缝；有袖上衣第一步因32次Newton内尚未平衡拒绝，552个真实self项和完整双路径均已计算，状态未提交。当前正在改善求解效率，尚无完整重力稳定成衣通过。
- 精确可见人体距离／三方向体内判定已通过54套实际人体、26,760个表面点和540次独立全扫描／立体角对照；双SDK实际静态链接通过。旧1cm人体场在脚眼等局部误差超过3mm，保持为历史算法资源，新增最终验收使用可见网格本身。当前人体仅有限拟合，尚未独立适配全部26项尺寸。
- 包含人体Newton与可见浮点环境桥的706份输入App冻结快照，iOS及Simulator Release均实际构建成功。后新增整衣self目标、缓存、精确人体查询和时间推进不在该App快照范围；没有据此宣称新路由或真机运行通过。

`GarmentCodeDrapeView.prepare()` 仅将恰好包含 `wb_front`、`wb_back` 的独立腰头送入 `WaistbandAssembly → PreparedInput → SewnDrape`；其余送入 `SkirtDrape`，后者仅接受受限的双片对称圆裙或双片裙。新增 `CircleAssembly` 没有被 App 调用。

## 12 款主版型

| 款式 | 当前状态 | 已有证据 | 剩余工作 |
| --- | --- | --- | --- |
| Shirt 宽松上衣 | 缺少完整 3D 链路 | 2D generator present; generic flat mesher validates representative front/back torso panels only. | Runtime torso/arm placement, neck/arm openings, all real center/shoulder/side seams, full 3D solve and App route are missing. |
| FittedShirt 合体上衣 | 缺少完整 3D 链路 | 2D generator and representative flat darted torso meshes present. | Bust/waist darts, strapless support and complete source-facing sewn assembly have no garment-level 3D proof or App route. |
| StraightWB 直条腰头 | App 部分可用 | Separate source particles and actual side sewing are wired. Default+2 mm seam perturbation pass alongside FittedWB (4 CLI cases total). Native UI medium/soft verified. | Full catalog width/waist and low-rise regimes, additional bodies and composed outfits remain unverified; upper edge remains a numerical fixed support. |
| FittedWB 贴体弧形腰头 | App 部分可用 | Real annular source geometry, independent particles and side sewing wired. Default+2 mm perturbation pass. Native UI medium/firm verified. | Same catalog/combination gaps as StraightWB; it is not already sewn to skirts/pants/tops. |
| SkirtCircle 圆裙 | App 部分可用 | App uses legacy structured source mesh with welded equal-length sides. Current body-surface report has .5/.75/1 cases; native .75 UI verified. New separate-particle factory has .5/.75/1 prepare proof and one explicitly limited .75 3D smoke, not wired. | Catalog suns 1..1.95, cuts, low rise and combinations remain unsupported. New factory nil-limiter physics and .5/1 3D not verified. Replace/extend App route only after end-to-end proof. |
| AsymmSkirtCircle 不对称圆裙 | 缺少完整 3D 链路 | 2D source exists; curve meshing is only a reusable primitive. | Current circle adapter requires equal front/back radial geometry and rejects this family; needs real asymmetric placement, seams, gravity/contact and App proof. |
| Skirt2 双片裙 | App 部分可用 | Legacy welded side-seam solver is wired. Five body-surface cases (default/longer/flare10/soft/firm) and medium/soft UI verified; gathered waist is an auxiliary corrugated fixed support. | True free waistband attachment, ruffle 1.5..2, bottom cut, low rise and complete outfit assembly lack integration. Existing shape is not a sewn real waistband. |
| SkirtManyPanels 多片裙 | 缺少完整 3D 链路 | 2D n_panels and panel_curve branches exist. | No actual n-panel 3D placement/sewing/contact/output acceptance or App route; test 4..15 panels and every catalog curve option. |
| PencilSkirt 铅笔裙 | 默认数值通过，接缝外观待修 | 默认完整两片、4组后片省道及8组源接缝从初态运行744步，经24宏步R验收返回真实OBJ；侧边整缝另有8.77mm自由节点裂隙。 | 修复eased连续边闭合并重验外观；开衩、斜下摆、Sun/logo切口、全部尺寸／组合、个人合体、App通用入口及真机仍未验收。 |
| GodetSkirt 插片裙 | 缺少完整 3D 链路 | 2D base Skirt2/PencilSkirt plus real insert panels/stitches exist. | Must retain every insert and cut-mouth seam, folded waist darts for Pencil base, all insert counts/depth/width and contact. No full 3D factory or App proof. |
| SkirtLevels 多层裙 | 缺少完整 3D 链路 | 2D supports four base choices and three tier choices with true joined edges. | Tier placement, level_ruffle free nodes, 1..5 levels, mixed asymmetry and full-body/self contacts are missing. |
| Pants 裤装 | 缺少完整 3D 链路 | Actual left/right leg and cuff construction placement passed official source checks; no-upper WB now uses pants.rise with independent official geometry proof. | Crotch/center and in/outseams, per-leg cuffs, free waist attachment and complete body/self-contact physics still lack garment-level proof and an App route. |

## 组件与关键参数能力

| 功能 | 当前状态 | 已有证据 | 剩余工作 |
| --- | --- | --- | --- |
| 前/后领口 7 种 × 对称/左侧配置 | 只有基础/平面验证 | 2D supports CircleNeckHalf/CurvyNeckHalf/VNeckHalf/SquareNeckHalf/TrapezoidNeckHalf/CircleArcNeckHalf/Bezier2NeckHalf. Generic Bezier/circle mesher exists. | Each real upper neckline must remain an open boundary with correct fit/normal and seam attachment; no upper 3D exists. |
| Turtle / SimpleLapel / Hood2Panels 独立领部 | 缺少完整 3D 链路 | 2D panels and connection stitches exist. | Neck/collar/hood/lapel placement and facing, hood center seam, lapel standing branch and genuine torso/neck contact unverified. |
| 有袖/无袖、3 种袖窿、袖角与开口方向 | 缺少完整 3D 链路 | 2D ArmholeSquare/ArmholeAngle/ArmholeCurve, sleeve angle/length/width/orientation exist. | Attach actual sleeve to armhole including right_wrong/direction, arm pose, free cuff edge and shoulder/body contacts; no sleeve 3D acceptance. |
| 立肩及立肩长度 | 缺少完整 3D 链路 | 2D standing_shoulder branch present. | Real three-dimensional shoulder placement and sustained seam/shape proof missing. |
| 袖口/裤口 CuffBand / CuffSkirt / CuffBandSkirt | 缺少完整 3D 链路 | 2D independent bands/flounces/mixed cuff panels and joints exist. | Attach all actual pieces with top_ruffle/skirt_ruffle, skirt_fraction/flare and source lengths; test both arms and both legs. |
| 左右不对称上衣及单侧无肩带 | 缺少完整 3D 链路 | 2D left.enable_asym and left shirt/collar/sleeve variants exist. | Do not mirror one solved half over a different source; all left/right panels and seams need independent placement and proof. |
| 同片胸省/腰省/裙裤省道 | 只有基础/平面验证 | Sewing/shared dart-tip contact tests exist; generic mesher accepts representative darted FittedShirt source loops. | Actual garment-level dart folding, correct side/facing, no crossing at tip and unchanged source metric have no 3D acceptance. |
| 圆裙/双片裙/铅笔裙开衩与装饰切口 | 只有基础/平面验证 | Generic flat mesher includes cut Skirt2 and concave U examples. | Preserve open cut/slit edges in assembled surfaces, do not close across them; current skirt adapters explicitly reject cuts. |
| 抽褶、吃势与保留自由褶节点 | 只有基础/平面验证 | Sparse finite-tack plans, true free-node checks and source-edge refinement request -> actual remeshing pass in Sewing tests. | No actual gathered/eased composed garment 3D solve is yet accepted; fixed corrugated Skirt2 support is a different experiment. Define intent from verified known programs rather than guessing imports from ratio. |
| 低腰及腰头与下装腰位一致 | 缺少完整 3D 链路 | 2D catalog rise .5..1 exists. Pants+WB uses the same pants.rise; two WB types and independent skirt.rise perturbations pass official geometry checks. | Standard-body skirt assemblies still require natural waist. Genuine low-rise support/contact and complete free lower-body attachment remain unverified in 3D. |

## 组合款

| 组合 | 当前状态 | 必须补齐 |
| --- | --- | --- |
| 腰头 + 每种裙装/裤装 | 缺少完整 3D 链路 | Current standalone factories reject additional panels. Combine full source document, preserve all attachment lengths/intent, pin only appropriate garment support and let waist joins move. |
| 上衣 + 腰头 | 缺少完整 3D 链路 | Upper placement and torso-to-band actual joints must be added. |
| 上衣 + 下装（无腰头） | 缺少完整 3D 链路 | Direct waist interface joins, lengths/ruffle and support strategy absent. |
| 上衣 + 腰头 + 下装 | 缺少完整 3D 链路 | Full connected garment, every source piece/join and inter-component contact unverified. |

组合必须以完整原纸样的 SHA、全部裁片与所有真实接缝为单位验证。不能删除未支持组件后显示一部分，也不能把腰头和裙身两个独立固定预览摆在一起当作已经缝合。

## 人体、求解和 App 交付

| 能力 | 当前状态 | 已有证据 | 剩余工作 |
| --- | --- | --- | --- |
| 二维裁片 → 人台周围初始装配 | 部分完成 | Circle/WB/Skirt2 have specialized initializers. Imported JSON retains placement fields; newly generated PatternFile deliberately sets translation/rotation zero and includes_3d_placement=false. | General source-faithful placement for torso/arms/legs/darts/tiers/inserts/collars and valid imported rotation/translation is absent. A flat mesh alone does not satisfy this step. |
| 源边长/面积/质量/完整源 SHA 与三角法向 | 基础已验证 | PreparedInput validates all panels, disjoint particles, complete source boundaries/stitches, directed faces, mass and same collision/render body; read-only panelBindings retained. 38 negative/cancel/budget cases recorded. | Each new factory must pass this full factory with its complete document and supply actual runtime integration evidence; do not bypass for complex shapes. |
| 真实缝合方向、正反面和连续普通边 | 部分完成 | Sewing accepts explicit A/B direction and rightWrong metadata; WB genuine ordinary seams accepted. Legacy skirts are welded controls. | Current adapters reject rightWrong=true. All actual non-WB seams, mixed facing, one-to-many subdivided interfaces and same-panel darts require explicit known mappings and integration. Weldequal seams alone cannot prove independent sewing. |
| 同源人体距离场/面接触/布片自接触 | 基础已验证 | Full visible closed-body mesh and SDF, actual body triangle intersection checks and cloth contact tests exist. Body-surface report covers 8 skirt cases, not all clothes. | New sleeves/collars/crotch/tiers/layered regions need discrete final intersection and independent inside/outside/centroid tests plus visual pose checks. Current scheme does not provide continuous collision guarantees. |
| 人体尺寸与姿态 | 部分完成 | Full CC0 mesh is visible; fitting uses height/waist/hips/hips_line/_waist_level with bounded scaling, same body used for rendering/contact. | Bust, underbust, neck, shoulders, arms/wrists, thigh/crotch and arm_pose_angle do not independently fit this mannequin. Upper/leg assembly needs either dimension-consistent fitting or explicitly validated body-shape limits; no personal scan is required. |
| 柔软/中等/挺括实验面料 | App 部分可用 | 120/180/280 g/m² numerical presets, SI reference area mass, compliance/damping and material regeneration are implemented. Supported garment UI preset changes recorded. | No measured cloth calibration (user explicitly accepted experimental presets). Verify each new garment remains stable and preserves area/mass under all presets. Do not turn lack of unavailable sample measurements into a requirement for this phase. |
| App 旋转/缩放/接缝/人体显示/复位 | App 部分可用 | RealityKit native preview and actual supported-skirt/WB UI records exist; WB close camera handles full-body orbit bounds. | Composed garment/full-body framing, upper/lower/hood/extreme sleeves views, multi-component seam identity and all new UI routes need final native verification. |
| 离线后台生成/进度/取消/失败 | App 部分可用 | Task.detached, progress callback, runID freshness guards, cancellation and visible quality/failure summary present. Core cancellation tests exist. | Complex preparation is still actor-bound; measure UI responsiveness/cancel during meshing, preparation and long multi-panel solve, plus no stale result after dismiss/configuration change. |
| 实际 3D 数据导出 | App 部分可用 | OBJ metre/Y-up cloth+body export and local Files export proven for soft Skirt2 and StraightWB. | All new multi-panel source identities, faces/normals, seams and final geometry need export/reimport verification. OBJ currently uses one cloth object name with skirt/WB cases; add appropriate full-garment naming. GLB/AR are not explicit newly authorized deliverables. |
| 重复生成/保存的输入与输出来源 | 未实现 | UI holds output and temporary OBJ for current view; no 3D cache/session archive was found in inspected 3D files. | If repeated results/session saving are retained in current product plan, bind source/body/material/solver version to cached output and invalidate correctly; not required to reproduce obsolete Unity/GLB plan blindly. |
| iPhone 17 Pro / iOS 27.0.1 真机性能 | 未实测 | Recorded Release simulator/generic iOS builds pass and actual Simulator UI runs exist. Explicit separate Circle .75 smoke reports 56.7 s on Mac. | Physical device run, elapsed preparation+solve/render time, peak memory, responsiveness/thermal behavior and largest supported full garments remain unmeasured. Mac/Simulator timings are not a phone benchmark. |
| GarmentCode / Design2GarmentCode 效果对照 | 部分完成 | Pinned official 2D source geometry and public qualitative 3D reference reports retained. Report explicitly says no matched official final 3D mesh. | For each completed family, compare same input source/panel topology, named 3D views and shape changes. Numeric 3D equivalence cannot be claimed without matched official body/material/final mesh; functional equivalent iOS backend remains allowed. |
| 保留二维/打印功能 | 部分完成 | run-acceptance.sh covers source geometry, interfaces, import, localization, seams, PDF/manufacturing and basic adapter. 3D suites deliberately separate. | After shared model/generator changes rerun affected 2D/printing gates and show current source paper/export bytes unchanged. Existing 356-pattern 2D claim is not 3D coverage. |

## 已检查的证据与边界

- 当前独立腰头报告的 33 个生成文件哈希全部匹配；4 个真实独立粒子案例通过。其来源代码中 `PanelMesher`、`SewnInput` 已因后续改进发生变化，因此该报告保留为真实运行快照，不能通过改写旧哈希冒充新版本运行。
- 人体面接触报告是 5 个双片裙、3 个圆裙的实际末态对照；不是所有款式的 3D 验收。
- 新圆裙工厂 `.5/.75/1` 只完成构造验证；独立 `.75` 严格 3D 探索测试显式启用 5% 限制目标并通过，Mac 约 56.7 秒。关闭限制的物理结果、`.5/1` 的该后端物理结果和手机耗时尚未验证。
- 原生 UI 记录只涵盖受限裙装和独立腰头；`physicalDeviceTested` 为 `false`。
- 356 项二维对照、15 片通用平面网格、38 项无效输入拒绝、标量缝合通过，各自证明对应范围，不能合并推导成完整成衣已完成。
- 当前没有同人体、同材料、同输入的官方最终 3D 网格，不能宣称 GarmentCode / Design2GarmentCode 数值三维等价。

## 完成审查所需证据

1. Every supported garment family and named discrete component has actual full-source placement, sewing and App routing; no panel/component is silently omitted or approximated by another style.
2. Representative default nonempty meta selections (80 known 2D combinations), both existing body profiles, each named component choice and critical size/rise/ruffle/cut limits have explicit 3D outcomes. Distinguish geometric/physical input failures from unsupported implementation gates; do not require all infinite continuous combinations to settle.
3. Complete source SHA/bindings/edge rest lengths/area/mass/source-facing normals and real seam gap/fold freedom are independently checked for each new integration.
4. Original convergence gates remain: strain <8%, sustained speed <.025 m/s, penetration estimate <3 mm, actual independent seam gaps <.5 mm, nondegenerate mesh, final cloth and body crossings zero; inspect actual positions and independent body volume samples, not only counters.
5. Native preview and OBJ saved through UI match the actual completed output; body/material changes invalidate results, cancel prevents stale publication, source 2D/PDF behavior remains intact.
6. New family views and parameter response are compared with pinned source/reference behavior; matched official 3D numerical parity is explicitly unproven unless evidence becomes available.
7. Current Release simulator and generic iOS builds plus actual target iPhone performance/interaction evidence cover the new completed family scope; Mac/Simulator timings alone do not satisfy phone measurement.

连续参数不可能穷举；需把每个目录参数映射到实际装配能力，覆盖全部离散分支与有意义的边界/扰动，并对无效或物理不成立的输入保留清楚、可复现的失败。不能把人工缩小的实现支持范围当作原目标已经完成。

## 可复查来源

- [`GarmentCodeParameterCatalog.json`](../../TrailorAss/Resources/GarmentCodeParameterCatalog.json)：全部款式、参数与范围。
- [`GarmentCodeNativeGenerator.swift`](../../TrailorAss/Models/GarmentCodeNativeGenerator.swift)：完整二维组合分派。
- [`GarmentCodeDrapeView.swift`](../../TrailorAss/Views/Garment/GarmentCodeDrapeView.swift)：实际 App 路由、后台任务、预览与导出。
- [`GarmentCodeSewnInput.swift`](../../TrailorAss/Models/GarmentCodeSewnInput.swift)：源数据与装配验证边界。
- [独立腰头数值快照](Reports/2026-10-25-waistband-sewn/manifest.json)、[原生 UI 记录](Reports/2026-10-25-waistband-sewn/ui/verification.json)。
- [人体面接触对照](Reports/2026-10-25-body-surface/comparison.json)。
- [`CircleAssembly.swift`](CircleAssembly.swift)、[`PanelMesher.swift`](PanelMesher.swift)、[`Sewing.swift`](Sewing.swift)：分别证明构造、平面网格和缝合基础，不能互相代替。

## 最新物理路径诊断：Native129

原生129项测试、两SDK链接与独立正间隙证明通过，根复核绑定了1145份源或证据文件；该库还未包含在最近一次App123实装中。新生产690步仍未提交。与旧保存路径不同，这次实际圆裙候选在整步直线上出现两处真实边穿越，独立精确根隔离已确认，碰撞拒绝正确。后续两个真实半步诊断已全部通过，独立逐位运动学复核也通过；正式S／R子步接入与回滚、逐叶验收控制正在验证。原质量、材料、接缝、碰撞与最终稳定门槛保持，当前没有新整衣或通用App入口通过。完整来源见 [整衣计算验证](JOINT-GARMENT.md) 及JSON账本末尾记录。
