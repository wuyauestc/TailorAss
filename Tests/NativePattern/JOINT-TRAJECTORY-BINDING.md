# 实际静态轨迹与已检查候选的绑定

正常Newton候选已经通过能量、源形变、人体和self连续检查后，数值ULP竞争仍可能找到更好的候选。前一个候选只是“检查通过”，没有执行；它必须保留在尝试统计里，不能多算为实际配置轨迹。

旧 `GarmentCodeJointSimulation` 要求 clear checkedLines 数量与N.acceptedTrajectory数量相等并逐项zip。真实406数学帧中分别出现14条实际段/16条clear候选、23/26以及最终v2的9/18，这条旧断言会错误拒绝安全实际轨迹。旧S源码SHA为 `62f785c30d3bcd2e208fa2fb8fe620937a674ef03d3e92118d099abf4b4f4e26`，原证据保留。

## 生产绑定

`ConfigurationLineEndpoints(previous:candidate:)` 仅是端点数据。纯函数
`configurationCertificateIndices(initial:final:trajectory:checkedLines:isCancelled:)`
返回按时间顺序精确匹配的候选序号，不产生物理资格、人体能力或Session状态。

- 实际轨迹最多96段，clear候选最多192条，对应原96次Newton每次至多一个暂存正常候选和一个实际提交候选；不扩大原Newton次数、单次查询预算或几何门槛；192是明确的绑定记录存储上限，额外候选的实际查询仍全部计入尝试统计。
- 每条实际段必须从前段末态开始，非零，最终到达真实N末态；端点顶点数和有限性先验证，匹配逐Double.bitPattern进行，±0不混同。
- 从上一个匹配点之后向前扫描checkedLines，只允许实际轨迹成为它的有序子序列；缺失、证书逆序、不连续、错误末态、预算及取消均失败，不返回部分索引。
- `advanceStep` 再核选中索引处真实source Motion、body及self报告的完整性和domain，才生成实际 `ConfigurationSegment`。跳过候选不删除path.calls、原始查询数、时间或拒绝/补证统计。
- 只改静态配置折线绑定。重力、settling的整帧物理直线路径、力/P修正/Pz、源边/接缝/速度/稳定24步及最终独立验收条件均不变。

## 聚焦回归

```sh
python3 Tests/NativePattern/run-joint-trajectory-binding.py \
  --package-proof /path/to/verified-native117-proof
```

runner复用已验证原生静态库，仅编App Swift；保持已有 `JointSimulation.swift` 的实际两款初始0→8步、早/中取消、1次Newton预算和强制self路径预算控制，只在冻结副本主入口前插入两组独立聚焦检查。没有重新运行完整衣服或构造假的稳定Session。

`JointTrajectoryBinding.swift` 验证跳过未提交候选、真实零运动、缺失/逆序/断链/末态/零段/数量/NaN/±0、取消与96/192预算。必要完整真实输入压缩于 `Fixtures/3d-joint-trajectory-binding/actual-406-lines.json.gz`；manifest保留原406各文件SHA、原路径和解压payloadSHA。14/16与23/26均逐原生body/self和源报告核验后，交给同一生产helper，未重新计算布料状态。

最终v2真实406保存内部位置的额外整合由独立driver完成：18条typed native clear查询正确绑定9条实际段，序号 `[1,3,5,7,9,11,13,15,17]`，fresh KKT仍满足原阈值，没有Session晋升。证据保留于 `/private/tmp/TailorAssShirt406Representability-kvm4gwze/final-v2-S-binding`，并绑定其独立交付清单。

## 竞争候选的特殊边界

`JointCoordinateCompetitionBoundaries.swift` 自身拥有测试错误类型，可独立并入纯N长期runner，无需依赖S或绑定专项。两组一致耦合二次目标保留真实E/g/H，分别验证：

1. 正常候选已完整通过，额外两个坐标候选的delta都显式精度未定：只记一条搜索汇总和2个unresolved计数，保留已证正常段；未确认候选不被接受。
2. 两个坐标候选虽能下降，但真实增量不优于正常候选：保持正常候选，仅它的完整路径被调用，不混合两个移动。

保留正常候选是安全的，因为比较期间原x、材料、source/rest/mass和已证候选均未改变；接受仍依赖它之前完整通过的原能量和所有路径。额外候选的取消仍抛错，不可借正常候选绕过；未知比较不变成安全或能量下降证据。实际接受方向的linear报告继续描述实际方向，坐标方向不能借用原CG converged标志。

此专项证明静态证书绑定与有界数值候选处理，不等于完整成衣、个人体型拟合或所有款式已验收。


最终聚焦证据：`/private/tmp/TailorAssJointTrajectoryBindingFinal/summary.json`，一次真实Swift-only编译后，两款各8步及所有取消／预算／状态不提交检查均终态0，全部输入SHA未变。压缩fixture另将831,360个端点坐标与原CP文件逐binary64核对（保留−0语义），无差异。最终S SHA为 `8ea3fa020fe15281e6b2e0ad60950442dda9f5c3f92360628f7f2d45cec083b7`。

最终iOS17 arm64完整实际模型严格typecheck在 `/private/tmp/TailorAssJointTrajectoryBindingIOS` 通过，复用已验证Native117模块和实际C模块映射；不声称设备运行或整App构建。独立的纯N长期suite已由root使用最终Native123通过，索引 `/private/tmp/TailorAssJointNewtonCompetitionFinal123/delivery-manifest.json`，未混称本次S八步或原生117现场重跑成123。

本项最终交付索引：`/private/tmp/TailorAssJointTrajectoryBindingDelivery/delivery-manifest.json`。它绑定当前S／独立测试／真实fixture／文档、所有实际命令与原始406整合证明；原运行与旧源码证据不覆盖。
