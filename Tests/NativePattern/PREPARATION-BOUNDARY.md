# 原生装配的后台准备边界

此改动只拆分 3D 求解前的准备工作。它不改变纸样计算、网格算术、初始化算法、接缝质量阈值或布料物理模型，也不表示已经形成可穿着的成衣。

## 接口与线程归属

1. 在 `MainActor` 调用 `GarmentCodeNativeAssembly.capture(document:body:design:settings:limits:initialization:isCancelled:)`，取得不可变、`Sendable` 的 `Recipe`。
2. 在一个可取消的后台任务中调用同步、`nonisolated` 的 `GarmentCodeNativeAssembly.build(recipe:isCancelled:)`，得到 `Sendable Preparation`。调用方继续执行自己的数值准备与模拟。
3. 原有 `prepare`、`prepareWithReport` 是同步兼容入口：依次执行同样的 capture/build。UI 需要使用两个阶段才能避开后台阶段的主线程阻塞。

`capture` 保留参数访问、完整原生参数重生成与 SHA 比对、构造矩阵、已知原生接缝意图、标准人体资源加载。`GarmentCodeStandardBody` 的 `MainActor` 缓存和 `load` 没有移动或绕过。

`build` 持有每次请求独立的网格缓存与细分字典，执行真实曲线采样/三角网格、接缝驱动的局部细分、刚体人体与布片间隙准备、最终位置下重新建立的缝合计划、面积质量积分、接触拓扑和完整源验证。不同任务可以并发读取同一个 Recipe。

Recipe 的构造函数限制在原文件内。它持有全部规范化源 JSON `Data`、其 SHA-256、完整源几何、保持原索引顺序的接缝及 right/wrong、原生接缝 hints、全部刚体矩阵、设置、预算、初始化模式、版型标识，以及**同一份**拟合人体 Snapshot 和兼容代理。后台没有接收 `PatternFile`、人体参数或服装参数的 actor 所有权。

## 来源检查仍然独立完整

`GarmentCodeSewnDrape.SourceReceipt` 的构造函数同样受限。后台重新计算实际保留的 JSON 字节 SHA，而不是相信一个 SHA 字符串。`GarmentCodeSewnDrape.prepare(input:plan:source:bindings:isCancelled:)` 与原 document 入口共用完整验证：

- 全部源裁片、顶点与三角面的独立 ID 和精确参考位置；
- 原曲线参数点、独立积分的弧长和 Green 面积、完整有向边界、单连通一致定向网格；
- CCW 参考面与原裁片模拟法向、每条真实结构边的参考长度与同片弯曲边；
- 真实源面积质量、质量尺度、每个顶点的归一化逆质量；
- 同一份可见人体、SDF 人体和面接触人体；
- 完整源接缝索引、方向、right/wrong、锚点/附着点/角点去重、原长与抽褶/吃势的自由边界节点、连续接触元数据。

Receipt 不授权未知导入获得已知原生的接缝意图；NativeAssembly 的 capture 仍要求完整参数重生成与原文件的规范化 SHA 相同。

## 取消与 UI 集成责任

后台函数同步检查 `isCancelled`，不自行创建任务。调用方应在真正执行 build 的 detached task 内传入 `{ Task.isCancelled }`，在父任务取消时显式取消该 detached task，并用请求标识阻止旧结果发布。只取消等待者不能取消独立后台任务。这里的专项没有修改 UI，也没有声称验证了 UI 的旧结果发布防护。

## 验证

运行 `sh Tests/NativePattern/run-preparation-boundary.sh`。它使用 Swift 5、默认 MainActor、完整并发检查和 warnings-as-errors，冻结编译输入、记录其 SHA-256，默认使用唯一输出目录；可通过 `GARMENTCODE_PREPARATION_OUTPUT` 设定输出、`GARMENTCODE_PREPARATION_KEEP_SNAPSHOT=1` 保留编译快照。

专项覆盖袖子、帽子和多层组合：两次相同 Recipe 的并发结果与旧入口完整状态签名一致；执行至少 200 次实际后台轮询时取消；显式 Task 取消；源点、法向、面积、参考长度、总质量、逆质量、人体来源、缺片和不完整接缝九类损坏拒绝。后台执行时每 10 ms 申请一次 MainActor 心跳，分别报告 capture 与 worker 用时，避免把 capture 的耗时隐藏在后台指标中。

2026-10-26 本机实测（准备阶段，没有 cloth dynamics）：

| 样例 | 顶点/三角面 | MainActor capture | worker | MainActor 最大心跳间隔 |
| --- | --- | --- | --- | --- |
| 袖子 | 1732 / 2710 | 0.198 s | 0.695 s | 15.14 ms |
| 袖子和帽子 | 2442 / 3786 | 0.510 s | 2.823 s | 16.12 ms |
| 贴体上装、腰头与多层裙 | 2415 / 3832 | 0.147 s | 3.125 s | 15.50 ms |

这些是 Mac 上的单次测量，运行时还有其他测试负载；不能推断 iPhone 性能。capture 仍有最长约 0.51 s 的主线程工作，因此本改动并不证明完整生成流程已经无卡顿。

实际运行的冻结输入和原始结果保存在 `/private/tmp/TailorAssPreparationBoundaryRun-20261026-7j25jgz7/boundary-source` 与 `boundary-actual-output/summary.json`。`actual-run-preservation.json` 记录了本次最初使用默认路径覆盖的 scratch 输出；未修改任何历史报告或旧 golden fixture，未用更换 hash 冒充复跑。其他完整兼容性回归使用本次唯一目录，结果以各自原始 summary 为准。

完整旧功能回归：本次唯一目录 `mesh-compatibility-verified/compatibility-summary.json` 的 189 份完整网格、233 份 JSON 全部逐字节一致；源快照 `/private/tmp/TailorAssRecoveryCompatibilityBuild.CO1nXT/source` 保留。`acceptance-combined-summary.json` 记录完整既有 356 组二维对照以及导入、中文、接缝、整张/A4 PDF、缝份、制造标记、基础模式和下装分支的通过。冻结验收副本最初遗漏 `Services`，PDF 编译因此失败；原始失败日志保留，补齐未修改的 exporter 后仅从失败阶段继续，六个剩余阶段全部以 0 退出。没有把这个打包失败写成产品回归。

装配兼容性：实际 Swift 测试完成全部 211 例（`caseCount=211`、`complete=true`、无 unexpected/known incomplete），逐例三个旧模式的 633 项完整状态签名均相同。旧 `run-native-positive-clearance.sh` 的默认 `output_dir` 没有导出给测试程序，导致主 summary 写入 `/private/tmp/TailorAssNativeAssembly` 而 positive 输入写入 `/private/tmp/TailorAssNativePositiveClearance`；脚本的最后一步因找不到 summary 退出 1。该原始失败日志保留，没有把它声明为全脚本成功。实际 summary 与 211 个输入文件原样保存到本次唯一目录的 `positive-actual-output`，每个输入的 source/state 签名均与实际 summary 相同；`positive-actual-output-preservation.json` 记录原路径与逐字节 SHA。独立 C++/Python 后处理使用保留的原始验证器与这个唯一目录重新执行，不重做或修改已通过的装配计算。调用其他旧 runner 时应显式设置唯一 `GARMENTCODE_NATIVE_OUTPUT`，避免默认路径路由及历史 scratch 覆盖问题。

独立后处理最终以 0 退出，`positive-actual-output/positive-clearance-conclusion.json` 为 `passed=true`：211 例、633 个旧模式签名，源质量/法向/独立自由度不变、零人工固定点、人体/布片 proper 交叉及正面积共面交叠均为 0。独立实际跨片最小距离为 0.000050000999999994 m，同片非相邻最小距离为 0.000263847177542 m，零距离及 10 nm 内原语均为 0。Apple Silicon 上此验证器的 `long double` 实测尾数为 53 位，未宣称额外扩展精度。总证据入口为本次唯一目录 `final-validation-summary.json`。这些全部属于初始准备与来源兼容性，`physicalAcceptance=false`。

两个旧 document 入口另有焦点控制：`Sewn.prepare(document:)` 的 3 个正例与 38 个无效/取消/预算拒绝全部通过；`AssemblyBuilder.prepare(document:)` 的两种腰头完整初始/rest/质量/人体/缝合状态、原有模拟与 OBJ 控制也通过。Builder 最初因冻结副本缺少 6 个永久 Reports fixture 在构造前失败；未修改原 fixtures，复制并记录它们的实际 SHA 后单独恢复该控制，保留原 133 退出日志。最终输出见 `legacy-sewn-input`、`legacy-builder-final`。

旧 positive runner 的路径问题随后已修复：默认创建唯一 Results 目录，并向实际测试程序和后处理导出同一个 `GARMENTCODE_NATIVE_OUTPUT`。`python3 Tests/NativePattern/CheckNativePositiveOutput.py` 验证 shell 语法、两次默认输出目录不同、子进程读到同一路径，以及含空格的显式路径原样传递；没有为这项脚本修复重复运行 211 例。此前失败证据保持原样。
