# 完整 App 构建与资源验证

## Native137 App826：通用3D入口与连续吃势来源（2026-10-27）

完整Release由build-app-release.py在新目录/private/tmp/TailorAssAppReleaseContinuousEase137冻结并构建；主任务已读取整体终态0。设备arm64构建140.56秒、Simulator arm64／x86_64构建225.77秒，两实际xcodebuild均退出0，使用独立DerivedData，没有复用旧App或手工预编译Native归档。构建本身没有运行Native测试；其完整编译Sources及Package.swift与已执行137项测试的封存包完全一致，非编译文件本轮也没有差异。

独立只读检查确认826个工程、资源和原生依赖文件在复制前、复制后、构建后及检查时逐SHA一致，当前工作区也仍相同。实际SwiftFileList均被本轮SwiftDriver命令引用；C/C++编译对象进入相应原生目标LinkFileList，四个原生合并对象进入App最终链接。

| Release产物 | 实际架构/平台 | 工程Swift + Xcode生成Swift | Native Swift | 实际C/C++输入 |
| --- | --- | ---: | ---: | ---: |
| iPhoneOS | arm64 / IOS | 122 + 1 | 9 | 25 |
| iPhoneSimulator | arm64 / IOSSIMULATOR | 122 + 1 | 9 | 25 |
| iPhoneSimulator | x86_64 / IOSSIMULATOR | 122 + 1 | 9 | 25 |

每个架构额外的1项Swift是本次Xcode生成的GeneratedAssetSymbols.swift，单独保存路径及SHA，不混称仓库源。lipo与vtool实查两份最终Mach-O的架构、部署平台及最低系统17.0；所有编译／链接清单、对象SHA和原始非致命警告保留。设备／模拟器日志分别有30／60条固定Eigen/IPC整数窄化警告，没有修改配置消警告。

本版实际编入新的cube菜单（整衣3D实验／保留旧裙装腰头预览）、显式人台形状与参考摆臂选择、形状／姿态／面料的同步取消失效，以及Workflow对未完成抽褶整边证明的提前提示。实际生产文件SHA：

- NativeDesignView：258fc73364173c46c587c549a880692eea16d2bfd32939ba055f0b816a495f1c。
- JointDrapeView：cf9232e10121a244a6231055fe6140e9cfce2e677e55081b5bf102d5c45ebc94。
- JointWorkflow：e50df94f8373cd970b5e3f1aa38fb8b57518340ad43136370d92d302e59f5584。

连续吃势来源的Sewing为4a5a1d41…5821c1，SewnInput为cabbcd01…e51b13，S为d71bd731…902768，R为9e4a6390…3ee06；N为7ca4e43a…9b8d17，稳定能量增量D为efd674f4…91cfe。完整SHA均在构建源清单中。不能用此构建去背书随后修改的源版本。

两个实际App均17个包文件，全部14个源Resources文件在生产加载代码所需的相对路径上逐字节一致；Rig子目录未被平铺。模板／Rig／量法／辅助权重资源的静态SHA绑定及SDF网格文件名/尺寸一致。这是包内路径与字节检查，**本轮没有执行运行时Bundle查找或生产加载器**，不代替iOS实际资源读取。

只读检查目录为/private/tmp/TailorAssAppRelease137Inspection-ioukuc2g，包含inspect-release.py、inspection-summary.json、两份完整App文件清单、所有实际输入／链接对象和平台工具输出。统一封存由该目录的delivery-manifest.json绑定构建源清单、原始日志、xcresult、实际App字节和本说明。此前已完成的双SDK类型检查、9项真实ViewModel生命周期及真实抽褶准备后早拒绝另见[JOINT-DRAPE-VIEW.md](JOINT-DRAPE-VIEW.md)。

本轮独立检查没有触发编译、签名、安装、启动、UI操作或屏幕读取，只消费主任务已完成的Release产物。完整构建通过仍不表示全部款式、抽褶缝合、个人合体、动态人体或真机性能通过。

## Native129 App817：拟合人体凭证与时间分区来源（2026-10-27）

817个工程、资源及原生依赖文件在复制前后逐SHA一致。新快照完整构建设备arm64与Simulator arm64／x86_64 Release，实际进程均退出0（设备175.22秒、模拟器225.34秒）；两个平台分别使用全新DerivedData，从源码编译，未拼接旧812 App或预编译归档。当前全部Native包仍逐字等同封存129项测试包；本次App构建未执行Native测试目标。

此快照实际编入N `2609fe9f134d9953e5e875080faf2692eb564d3ab563b4789f7d95889fd299e2`、seed forest S `d81b850aa36f726f4a62b8c984fa25d9cf326deaca0c195eaa101607b79c61d7`、带fitted bodyModel映射的R `4a95a9e45e8422f9c7aec1a2328d31fcd086d47773d656356fc8ab6a1a61b4c3`，并包含共享形变Replay、表面拟合器、完整静态表面验证器和FittedBody私有来源凭证。验证器为`d325f3e8546144599960780bfef7e18e821e1a828cf31f4f073d3682d017b6f7`，factory为`93bbcc31ed171eee5fa883ee80ba478c177a5c056e73e70904af9520c7f4e339`。Builder／Kernel Input／SewnInput／Workflow的显式拟合人体入口亦在此完整构建内；默认人体和通用3D路由没有因构建而更改。

| Release产物 | 实际架构/平台 | 工程Swift + Xcode生成Swift | Native Swift | 实际C/C++输入 |
| --- | --- | ---: | ---: | ---: |
| iPhoneOS | arm64 / IOS | 122 + 1 | 9 | 25 |
| iPhoneSimulator | arm64 / IOSSIMULATOR | 122 + 1 | 9 | 25 |
| iPhoneSimulator | x86_64 / IOSSIMULATOR | 122 + 1 | 9 | 25 |

每个架构的实际SwiftFileList为123文件；额外1项为本轮Xcode生成的`GeneratedAssetSymbols.swift`。最终链接对象清单、全部75次C/C++编译任务和原始警告保留于`compile-details.json`。lipo/vtool核实实际架构、平台与最低系统17.0。两个日志分别有30／60条固定上游代码的非致命警告，未改配置或源码消警告。

全部14个资源在两个真实`.app`内的生产查找路径和SHA与快照一致，包括新增`GarmentCodeBodyFitAuxiliaryWeights.json`。辅助权重JSON的模板／Rig SHA、1117辅助点、135原可见重合点、1668权重项及CC0原MHW来源绑定均通过静态包核对；不冒充iOS运行时拟合或连续摆臂验证。构建结束时快照及工作区工程输入仍逐SHA一致；后续源修改不能沿用本次产物证据。

交付目录：`/private/tmp/TailorAssAppReleaseFittedBody129-mousd4un/`。完整源清单、实际编译／链接清单、xcresult、两份App文件清单和`delivery-manifest.json`均保留。Simulator可安装产物位于`simulator-permitted/DerivedData/Build/Products/Release-iphonesimulator/TrailorAss.app`。本轮未签名、安装、启动、操作UI或Device Hub；旧812及更早证据不变。完整构建通过不代表26项人体拟合、个体合身、动态人体路径、整衣稳定或真机性能已经通过。

### App817安装后的实际检查

后续安装、启动完成，三条设备操作均退出0，启动PID为98184；只读复核全部17个已安装文件SHA与上述封存App一致。原驱动最终退出1，原因是安装后的数据容器路径与安装前不同，不能将该退出码解释为安装失败。没有执行卸载或清除；由于缺少安装前内容基线，原用户数据保留状态未获验证。

唯一Device Hub读取被中止，没有取得新截图或可访问性状态，不能据此宣称UI通过或Mac锁屏。实机清单命令成功返回两个模拟器、未列出实体设备，目标iPhone17Pro连接尚未确认。此App不含随后生产D、S/R及Workflow修复。安装交付：`/private/tmp/TailorAssApp817UISmoke-2b6v6mnd/delivery-manifest.json`，SHA256 `be673d7d828790af61275e2a1cacdfc5d5e9fa5baa29443f38fdc26c7e6755e4`。

## Native129 App812：真实时间子步验收与表面量体资源（2026-10-27）

812个工程、资源和原生依赖输入在复制前后、完整构建及产物检查时逐字节一致。设备arm64与模拟器arm64／x86_64的Release均使用全新DerivedData，从实际源码完成编译和链接，进程真实退出0；未拼接旧归档或旧App。整个Native包与已封存129项测试快照完全一致，本次App构建没有执行Native测试目标。

此次实际编入Newton `bc91f4a181aeb0f0d5291e65a4368d6ca7651e105b531270fd63ba1ee3dbbff0`、真实时间子步S `3d798d256b71c0bb1b30756652e89e7f14d20717164ee52c062916d26a136190`、逐叶验收R `56490fe920664ccb3c81ae846fe8e9f5781db6cb622bb71b7339c2e5bf3c7d56`，以及新增`GarmentCodeBodySurfaceMeasurements.swift`和对应JSON资源；表面量体及人体拟合原型未接入默认路径。

| Release产物 | 实际架构/平台 | 工程Swift + Xcode生成Swift | Native Swift | 实际C/C++输入 |
| --- | --- | ---: | ---: | ---: |
| iPhoneOS | arm64 / IOS | 118 + 1 | 9 | 25 |
| iPhoneSimulator | arm64 / IOSSIMULATOR | 118 + 1 | 9 | 25 |
| iPhoneSimulator | x86_64 / IOSSIMULATOR | 118 + 1 | 9 | 25 |

各架构实际App SwiftFileList为119文件，其中1个为本次Xcode生成的`GeneratedAssetSymbols.swift`；仓库App源为118个。完整编译、生成Swift、C/C++任务与最终链接对象见`compile-details.json`。最终Mach-O经lipo/vtool核实对应架构、平台与最低系统17.0。

全部13个运行时资源在两个实际`.app`中的查找路径和SHA一致。新增表面量体资源的模板／Rig SHA绑定、13,380项visible映射亦通过静态包检查；这不替代iOS运行时量体、26项人体拟合或个体合身验证。设备／模拟器日志分别保留30／60条非致命警告，主要来自固定Eigen/IPC上游代码的整数窄化转换；没有修改源或编译配置消除警告。

交付目录：`/private/tmp/TailorAssAppReleaseNative129Adaptive-fvlmi5sd/`。构建命令、原始日志、xcresult、完整源／资源清单、产物文件SHA与`delivery-manifest.json`均保留。本轮没有签名、安装、启动App或操控Device Hub；旧App804及更早证据保持原样。完整Release通过不是整衣收敛或真机性能通过，逐叶验收的最终成功分支仍以真实完整仿真和稳定窗口为准。

## Native123 App804：当前 N/S 与参考测量（2026-10-27）

新冻结的804个工程、资源和原生依赖输入完成两个全新DerivedData的完整Release构建，设备与模拟器进程均真实退出0；没有使用旧局部typecheck代替构建。复制前后、构建结束及产物检查时，快照和工作区输入逐字节一致。整个Native包与已封存123项参考包完全相同，没有非编译文件差异；App构建没有执行Native测试目标。

此次包含Newton `bc91f4a181aeb0f0d5291e65a4368d6ca7651e105b531270fd63ba1ee3dbbff0`、实际配置轨迹绑定S `8ea3fa020fe15281e6b2e0ad60950442dda9f5c3f92360628f7f2d45cec083b7`、参考测量 `78713fa225a127e9d6f2d01d584c86c588d0dcd0ce5450f98e2a26d204d58859`。

| Release产物 | 实际架构/平台 | 工程Swift + Xcode生成Swift | Native Swift | 实际C/C++输入 |
| --- | --- | ---: | ---: | ---: |
| iPhoneOS | arm64 / IOS | 117 + 1 | 9 | 25 |
| iPhoneSimulator | arm64 / IOSSIMULATOR | 117 + 1 | 9 | 25 |
| iPhoneSimulator | x86_64 / IOSSIMULATOR | 117 + 1 | 9 | 25 |

实际SwiftFileList每个App架构为118个文件，额外1个是本次Xcode生成的`GeneratedAssetSymbols.swift`；不能混称118个仓库源文件。每架构的完整编译列表、对应CompileC任务、生成Swift与最终链接对象清单另存`compile-details.json`。没有接入旧App或手工预编译Native归档；两个隔离构建从实际源编译、链接原生输入。SDK和系统标准模块仍由Xcode正常使用。

最终Mach-O的架构、平台和最低系统17.0由lipo/vtool实查。全部12个运行时资源在实际`.app`中的代码查找路径和SHA与冻结源一致，Rig子目录、模板和骨架来源绑定通过；两个App的全部文件与二进制SHA分别保存。构建日志有30条设备／60条模拟器非致命警告，主要是固定Eigen/IPC上游代码的整数窄化转换；未为消警告修改源或编译配置，完整原警告保留。

交付目录：`/private/tmp/TailorAssAppReleaseNative123NbcS8ea-8dos_5f9/`。`source-manifest.json`、两份原始构建日志/xcresult、`inspection-summary.json`、`compile-details.json`及两份App文件清单均保留。最终封存见`delivery-manifest.json`及旁边`delivery-manifest.sha256`。

本轮未签名、安装、启动App，没有操控Device Hub或做新页面交互；不沿用旧795的安装截图来声称本次已运行。完整Release通过不等于整衣收敛、26项人体拟合或iPhone 17 Pro真机性能通过；当前求解结果仍需独立物理验收。旧795及之前全部记录和产物保持原样。

## Native117 App795 与可滚动纸样预览

795 个文件的冻结快照已完成 iOS arm64 和 Simulator arm64／x86_64 两个完整 Release 构建，实际进程均退出 0。116 个 App Swift、9 个 Native Swift、每架构 25 个 C++ 输入及 12 个资源核对通过；整个 Native 包与已验证的 117 项快照相同，求解器 SHA256 为 `5f3c325510793781a7baf2801692d53bfbe50e301b9a807b128637e21f74ef23`。App 构建没有重新执行 Native 测试。

Device Hub 中 iPhone 17／iOS 27.0 Simulator 的实际安装包 15 个文件与构建产物完全一致。通过真实交互确认：长轮廓警告完整显示；整页可滚动到底部导出；展开 JSON 后按钮仍可到达；异常纸样的 PDF／制版禁用而 JSON 保留。普通双片裙的裁片选择、接缝高亮、画布平移和适配全图正常，PDF／制版菜单可用。

交付目录：`/private/tmp/TailorAssCurrentFullAppReleaseFSC117Scrollable/`；`delivery-manifest.json` SHA256 为 `dbd22dac1fb93a7285d1e502ba6cdab1e5d5877a07bb8c267f7c5d91a07fb5c1`。截图、AX、构建命令、产物与安装绑定均保存。通用 3D 页面仍未路由；这不是整衣收敛证明，也没有验证 iPhone 17 Pro 真机性能。

## 历史 Native111 App788 与实际模拟器界面

冻结目录 `/private/tmp/TailorAssCurrentFullAppReleaseFSC111Arc/` 包含 788 个输入文件。iOS arm64、Simulator arm64／x86_64 的完整 Release 构建真实通过，116 个 App Swift、9 个 Native Swift、每架构 25 个 C++ 输入及 12 个打包资源均核对。源码仍与冻结清单一致；构建时工作区随后出现的 Native117 改动没有混入该 App。

Device Hub 实际安装到 iPhone 17／iOS 27.0 Simulator 后，15 个包文件与构建产物 SHA 全部一致。真实交互验证了自交参数阻止生成、同款有效参数重新生成、异常 JSON 导入警告和打印／制作／3D 禁用，以及系统分享存到本地“文件”后的原始字节保持。交付清单 SHA256 为 `7ff898b821fcff0f6d0bb482bdc3d91c58d551ba8c9542a163479869f1705a40`。

后来截图复查发现长警告挤出预览布局，源码已修正为可滚动页面，后续 App795 另行构建和实装验证通过；上述功能检查不能替代后续布局检查。该快照也不含后来的精确 expansion 碰撞补证及单 ULP 求解改进。完整说明见 [SOURCE-CONTOUR-DIAGNOSTICS.md](SOURCE-CONTOUR-DIAGNOSTICS.md)。

## 历史105项原生库快照

当前完整App的779文件输入在复制前、复制后及构建结束逐字节一致，工作区也仍与
冻结输入相同。设备版arm64／iOS及模拟器arm64、x86_64／iOS Simulator的Release
构建均实际退出0，部署目标保持17.0；两次进程均已读取终态。此次未签名、安装
或启动App。

实际编译输入检查覆盖每个架构的全部115个App Swift、9个原生库Swift和25个
C／C++文件；Mach-O平台和架构均符合对应目标。全部12个资源文件在实际`.app`
中的路径和SHA与冻结输入一致，骨架保留所需子目录，模板／骨架来源绑定通过。

原生全部546个`Sources/`文件和`Package.swift`与105项测试的冻结快照精确相同。
全包唯一差异是已在原生交付中声明的`README.md`文档后续说明，因此不能称整个
原生包逐字节相同。App构建没有执行原生测试目标，也未重复原生独立105项套件。

除实际包内标准人体和Rig恒等姿态读取外，还在Mac将同一生产
`GarmentCodeFixedBody.recipe → prepare`放入后台任务，分别读取两个实际App包。
默认`arm_pose_angle=45.483`的非恒等摆臂、B独立来源认证／重放、receipt校验和Q
精确查询绑定均通过，准备工作实际在非主线程运行。两包的固定表面与Q几何SHA
均为`1f34beb504708e9f5415e3e215e7265a6a82892f882828ea2fe5f68ba599917a`，
保留13,380点和26,756面。这只证明打包资源可被生产准备链读取，不是iOS启动、
布料仿真或个体人体拟合验证。

- 交付记录：`/private/tmp/TailorAssCurrentFullAppReleaseSelf105-_ag8ai6g/delivery-manifest.json`
- 交付记录SHA256：`2cb720e6d19d6a847a9e5b97ddacc9bdf1b5cf47980f586a7d1ab798b58ebc9a`
- 实际编译输入、资源和平台检查：同目录`inspection-summary.json`。
- 标准资源读取：同目录`resource-smoke/actual-app-resource-load.json`。
- 后台FixedBody认证及精确查询：同目录`fixed-body-resource-smoke-repaired/actual-app-resource-load.json`。

新增FixedBody测试工具首版因异步闭包直接访问`Thread.isMainThread`而编译失败，
原source、命令和日志完整保留在`fixed-body-resource-smoke/`。修正版仅将线程
观察与原`prepare`调用放入同步nonisolated包装，再从`Task.detached`进入；没有
修改App、工程或原生源。两平台App构建本身未发生失败。

## 历史746文件快照

2026-10-26 的冻结输入包含746个文件，复制前后及构建结束均逐字节一致。完整 `TrailorAss` Scheme 的 iOS Release（arm64）与 Simulator Release（arm64、x86_64）均实际编译、链接成功，部署目标保持 iOS 17。构建输入列表确认包含新的通用页面、后台流程、参数恢复、人体截面和骨架代码。

本轮修复两项集成问题：新页面显式导入 `Combine`，满足 Xcode 的 `MemberImportVisibility`；Xcode 同步目录明确保留 `Resources/GarmentCodeStandardBodyRig` 子目录，符合生产加载器的资源查找路径，避免骨架文件被平铺到包根目录。

检查实际两个 `.app` 内的人体网格、SDF、参数目录、骨架及许可文件，均与冻结源字节一致。另将生产 Swift 加载器编译为 Mac 测试程序，直接读取两个构建产物：13,380个人体顶点、26,756个面、骨架来源绑定及恒等姿态校验均通过。这是实际包内资源加载测试，不是 iOS 启动或成衣仿真。

- 构建与交付记录：`/private/tmp/TailorAssCurrentFullAppReleaseFixed-3vgr6hdg/delivery-manifest.json`
- 交付记录 SHA256：`588649b9a80c6e06103ab090a1939bd8f64c22f54e91c544a2d2d15da4552bf2`
- 实际包检查：同目录 `inspection-summary.json`。
- 生产资源读取：同目录 `resource-smoke/actual-app-resource-load.json`。

此前沙箱内包缓存访问失败、显式导入遗漏导致的构建失败及完整日志保留在 `/private/tmp/TailorAssCurrentFullAppRelease-u0vbr7sr`。最终检查脚本初版将 `/tmp` 与 `/private/tmp` 当作不同输入路径，错误报告未编译；原失败记录保留，使用实际路径规范化后检查通过，未重新编译或替换构建产物。

本快照所用原生接触库与已有87项测试的614文件快照一致；App构建本身没有执行库测试。当前通用页面仍未路由，未安装、启动本次构建，也没有证明完整成衣或目标手机性能。后续求解器或接触库修改需要新的构建证据，不能沿用本次结果。

## App804 后续安装与启动检查

上述804输入冻结构建随后实装到Device Hub的iPhone 17／iOS27.0模拟器。安装包15个文件（包括可执行文件及全部资源）与已封存构建逐字节相同，实际启动PID80913。普通双片裙真实生成2片，选中前片显示58.76×40.54cm、面积2,382.1cm²；接缝1配对高亮及PDF／JSON／制版标记菜单启用均经实际界面检查。截图、AX、安装命令及字节绑定保留于 `/private/tmp/TailorAssApp804UISmoke/delivery-manifest.json`，SHA256 `015fb38253fb733bea0b3ef4d818f4c56fb7d197c337742f4e8dbf191ce8b92b`。

最初普通沙盒命令因无法连接CoreSimulator在terminate阶段失败，未安装；取得工具执行许可后原目标安装、启动及资源核验均实际退出0。它证明本构建可启动及上述二维操作；没有重做PDF／JSON文件导出或旧裙装完整3D，也没有通用成衣或真机性能通过结论。通用3D路由保持未开放。

## App812 后续安装与启动

129项原生库与物理子步的812输入构建已安装到同一iPhone 17／iOS27.0模拟器，实际启动PID88637。16个包内文件与已封存Simulator产物一致，包含新增的人体表面量法资源；安装前也核对了全部源App产物哈希。三个安装命令实际终态均为0。

安装证据为 `/private/tmp/TailorAssApp812UISmoke/installation-manifest.json`，SHA256 `976bbf468cebe80077f6a39ce67de7f1c1ba4f6229f28808dc45491ed87a2869`。此时Mac已锁屏，界面工具明确拒绝继续，已请求用户解锁。该记录仅证明安装与进程启动，不证明本版UI、通用成衣或目标手机性能通过；后续界面检查单独记录。
