# 完整款式目录的纸样输入

这是后续整衣 3D 逐款验证的**输入目录**，不是 3D 验收报告。生成器只链接二维计算与原参数恢复模型，不链接布料、网格、碰撞或原生 C++ 包。

运行：

```sh
python3 Tests/NativePattern/run-native-catalog-inputs.py \
  --output /private/tmp/MyNativeCatalogInputs
```

输出中的 `inputs/catalog-input-manifest.json` 按稳定 `caseID` 索引每份完整纸样。`patternFile` 指向可供 `run-joint-result.py --pattern-json FILE --mode simulate` 使用的 PaperJSON；文件本身保持标准 `pattern/parameters/properties` 结构，不是自定义包装。`parameters/` 保存原始人体、派生人体值、原覆盖项、完整设计树和相对于该人体基准的变化。相同完整 source SHA 的案例共用纸样文件，但案例与覆盖记录各自保留。

已有的 R 入口仍会独立恢复参数、重建完整 source SHA、进行初始化、动力学、全部连续路径及最终验证。可以选择 `--body-pose legacyTemplate` 或 `--body-pose matchPatternReference`。本生成器没有执行这些步骤，也没有接受任何成衣结果。

## 冻结结果（2026-10-26）

本节保留原始目录快照。后续不对称接层修正重新生成全部 618 份输入，仅 8 个 source SHA 改变，其余 610 个及原 211 个保持；新目录位于 `/private/tmp/TailorAssNativeCatalogInputsLevelsHemFixed`。24 组独立上游对照与真实准备的 6 通过／2 预算拒绝见 [LEVELS-HEM.md](LEVELS-HEM.md)。纯输入导出成功仍不代表几何可裁剪或成衣物理通过。

最终证据：`/private/tmp/TailorAssNativeCatalogInputsFinal`。

| 输入来源 / 覆盖组 | 案例数 |
|---|---:|
| 原 80 种完整 meta 组合 × 默认、女性人体 | 160 |
| 全部既有上装 oracle 覆盖项及其原人体（含 30°/60°、领袖、左右不对称、无肩带） | 108 |
| 原 Levels-rise 完整组合 | 12 |
| 原 Composition-rise 完整组合 | 48 |
| 原 25 个下装分支 × 两个人体 | 50 |
| 原 27 个 source-mesh 定义 × 两个人体 | 54 |
| 原 3 个 Pants+裤口定义及女性重放 | 6 |
| 左侧独立领线 7 种 × 两上装 × 两人体，启用不对称 | 28 |
| 左侧独立袖窿 3 种 × 两上装 × 两人体，启用袖片 | 12 |
| 左侧独立袖口 3 种及 null × 两上装 × 两人体 | 16 |
| 左右颈线曲线翻转布尔分支 × 两上装 × 两人体 | 16 |
| 分层裙：4 种基裙 × 3 种层裙 × 两人体，实际生成 3 层 | 24 |
| 插片裙：2 种基裙 × 5 种插片数量 × 两人体 | 20 |
| 多片裙：8 种裁片曲率 × 两人体 | 16 |
| 两种侧切图形 × Pencil / Godet-Pencil / Levels-Pencil × 两人体 | 12 |
| 所选连续参数端点：圆裙展开、多片数量、裙层数量/抽褶、双片裙抽褶、直裙廓形、裤腰位 | 32 |
| 圆裙、非对称圆裙的开衩分支 × 两人体 | 4 |
| **合计** | **618** |

默认、女性人体各 309 例；全部 12 主版型都有两个人体的独立完整源输入。所有非 meta 的 **16 条 select/select_null 参数路径**在两个人体下均覆盖其目录选项，含独立左侧分支与 null；新增选择路径时生成器会明确拒绝旧覆盖清单，要求审查其实际消费者。覆盖项在对应组件启用时才计数，没有把禁用袖片下的袖口默认值算成有效组件覆盖。

618 例全部完成生成、纸样几何校验、严格原参数恢复和完整源逐字节重算；原 211 个初始化案例 ID 全部保留并可导出，原 27 个定义直接由共享 helper 读取。548 份唯一 PaperJSON 合计 24,616,040 字节。**当前生成拒绝列表为空**。两个独立进程导出的清单、参数与全部纸样文件逐字节一致。

这不是连续参数空间的穷举，也不是所有组件交叉组合的穷举。它明确覆盖上述目录选项、原有代表组合和选定边界；尚未检查这些输入的网格预算、3D 初始化或成衣稳定性。

## 身份、预算与失败记录

清单分别保存：

- `paperJSONBytesSHA256`：实际导出的 pretty JSON 文件字节哈希。
- `sourceSHA256`：整份 PaperJSON 以 `sortedKeys/withoutEscapingSlashes` 重新编码后的规范哈希，包括全部裁片、缝合、人体、设计与来源属性。
- `uiDocumentSignatureSHA256`：当前 UI 使用的 `GarmentCodeJointParameters.signature(document)`；现与 source SHA 使用相同完整规范编码。UI 最终 `configurationID` 还附加运行时人体资源与目录 URL，本任务不生成该环境相关 key。

显式输入预算为最多 2048 案例、每份 128 片 / 8192 源顶点 / 8192 源边 / 4096 源缝合、每纸样 2 MiB、唯一纸样总量 64 MiB、每参数侧录 512 KiB。本次实际最大为 16 片、134 源顶点、134 源边、58 条源缝合、86,112 字节。20k 网格顶点 / 40k 三角面的装配预算另标 `evaluated:false`，源点数量不能冒充网格数量。

失败不会缩放参数、删除裁片或回填默认值。清单保留 `rejectionPhase/reason/errorType` 与原参数；已生成的完整纸样即使后续来源恢复拒绝，也保留在 `generatedPatternFile`，只有全链来源检查通过才给 `patternFile`。程序退出 0 表示生成任务与覆盖/可重复性检查完成；必须另看实际拒绝列表，`completeGarmentAccepted` 始终为 false。

## 本轮修复的来源恢复缺陷

旧 `JointParameters.restore` 对每个组都把键名 `type` 当元数据比较；`sleeve.cuff.type`、`left.sleeve.cuff.type`、`pants.cuff.type` 实际是子参数。这让合法袖口/裤口修改被误判为目录版本不符。现在只有真实 `node.type != nil` 才比较 `type` 元数据；子参数继续接受原递归、键集合、范围、枚举和最终完整编码检查，没有放宽真实元数据约束。

专项使用两个人体下 24 份真实完整源（右袖口、左袖口、裤口，各 null/三种款型）作正控；10 项负控覆盖元数据 type/range/default_prob 篡改、缺子参数、非法枚举、子参数冒充元数据、多余键、缺值、缺腰围，以及合法参数配旧几何的完整 source 身份不符。

首跑 `/private/tmp/TailorAssNativeCatalogInputsFirst` 保留 46 个真实恢复拒绝；另 6 个 SIGGRAPH 失败来自当时测试快照漏拷已有图形资源，已修正测试 runner。第二快照只含测试编译错误，没有数值结论；第三快照的 546 例与最终新增左侧分支后的 618 例均全通过，没有覆盖旧证据。

恢复模型 SHA：`89af4bd09ce35e1de485921a66ab20c9d3b4f933205303710572879ba5fd3df7` → `4b53abdf28bef96c06c2c1960fddff97a47265be41eef224f241fd53e6f052fd`。没有修改参数生成计算、目录、网格、原生包、求解器或 App 路由。
