# 整衣后台生成流程

`GarmentCodeJointWorkflow.generate` 是 App 调用完整源整衣求解器的异步入口。它接收当前纸样、同一份人体与服装参数和实验面料，依次执行源捕获、后台准备、静态缝合、重力渐入、下垂与最终验收。返回值只能包含 `GarmentCodeJointResult.Validated`；初态、被拒绝候选、阶段进度或达到迭代上限均不能变成可展示的成衣结果。

主线程保留原生参数访问、源重生成与来源核对，以及结果收据的完整源绑定。曲线网格、细分、人体与布片间隙、接触构建及求解器准备运行在第一个 detached 任务。第二个 detached 任务串行拥有数值 Session、稀疏分解器和最终验收工作区，不会让 Session 跨线程共享。

父任务取消会显式取消当前后台任务，并等待该任务真正退出。后台正常结束或抛错与父任务取消同时发生时，均再次检查父任务取消状态，优先返回取消，防止过时结果或预算错误覆盖用户取消。未取消的工作线程错误继续按原类型传递。进度通过 MainActor 转发，以单调序号丢弃乱序和重复消息；整个请求退出后关闭转发，已排队的旧进度无法再发布。页面仍须以自己的请求 ID 管理多次生成、关闭和导出。

界面收到独立阶段：读取纸样、准备网格、静态缝合、重力渐入、下垂、验收、完成。阶段计数表示已经完成的工作，不是估算完成百分比。下垂可以在预算用尽前达到稳定，也可能在预算用尽后仍失败。静态装配次数不计作物理时间；最终时长由结果验收器按真实动态步骤计算。请求另外记录源捕获、准备和整个生成流程的单调时钟耗时。

三档材料统一通过 `GarmentCodeJointFabric` 选择本构参数与原面积质量密度。它们属于未实物标定的实验预设，测试范围见 [JOINT-FABRIC.md](JOINT-FABRIC.md)。原源数据和旧二维打印功能不由这个流程修改。

`bodyPoseSelection` 默认 `legacyTemplate`，保留原标准人台；显式选择 `matchPatternReference` 时，在后台准备按原人体参数的 `arm_pose_angle` 摆臂。同一份通过检查的实际表面供完整装配、碰撞和精确查询使用，不挂接旧逆SDF。默认参考角本身也不等于原人台姿态；具体量法、16组完整准备及限制见 [BODY-RIG-POSE.md](BODY-RIG-POSE.md)。姿态准备失败时不会进入数值推进。

每步、人体／自接触路径和最终验收耗时现统一使用 `ContinuousClock`。先前真实长跑中，`Date`累计值与外部单调时钟读数不一致；历史数值保留，不再据其推断性能。单调计时只用于真实计算成本，物理时间仍由固定 `dt` 和已接受动态步数决定。

## 验证

```sh
python3 Tests/NativePattern/run-joint-workflow.py --package-proof /path/to/verified/native/package
```

脚本冻结全部实际 Swift 输入和资源，用显式指定、已验证的当前原生库进行最终静态链接，只重编 App Swift。原生完整源文件集合与字节必须匹配该证明，不隐式链接旧库。编译采用 Swift 5、默认 MainActor、完整并发检查与 warnings-as-errors。原始源码、链接依赖及其 SHA 在运行前后核对，输出保存在唯一目录。

2026-10-26 的首轮实际结果位于 `/private/tmp/TailorAssJointWorkflowFirst/summary.json`：严格编译和8项控制均通过。控制验证父任务取消后子任务确实退出、已取消请求不启动子任务、子任务返回时取消仍生效、进度乱序／重复／结束后消息被丢弃；并用真实圆裙＋腰头的完整纸样执行后台准备时取消、数值阶段取消、第一步 Newton 预算拒绝及原纸样 SHA 不变。

后续姿态接入的冻结版本在 `/private/tmp/TailorAssJointWorkflowPoseAndMonotonic/summary.json` 通过10项真实控制：新增45°摆臂完整准备与源绑定后取消，以及实际90°人体折叠在进入推进前被拒绝。计时专项在 `/private/tmp/TailorAssJointResultMonotonicAndBodyCapabilities` 另通过两款R controls和16个实际装配步；各路径耗时非负、不超过所在步，总步耗时不超过外部单调计时。这些快照分别绑定具体源版本，后续P或接触增量改动须另行验收。

本证据验证异步编排和失败边界，没有伪造成功成衣来覆盖正向分支。通用页面还需接入、完整成衣正向验收和原生界面检查；当前测试不代表全部3D已经完成，也不代表手机性能。

2026-10-27的当前流程在`/private/tmp/TailorAssWorkflowBudgetCancellation`完成严格编译及12项真实异步控制；新增父任务取消与子任务预算错误竞争、未取消子任务原错误保留两项。生产流程和测试输入、实际命令及结果纳入`/private/tmp/TailorAssPhysicalResolutionOutcomeAudit/delivery-manifest.json`（SHA256 `e73c2c14fda5f0198a24ca48e8e01e0ecad62f15da527c59a9ed330f378a028d`）。本批仍无最终成衣成功输出。

正向流程可额外运行：

```sh
python3 Tests/NativePattern/run-joint-workflow.py --package-proof /path/to/verified/native/package --positive-waistband
```

当前`/private/tmp/TailorAssWorkflowPositiveStraightWB`已通过13项控制，其中新增真实默认直条腰头从纸样经App异步入口完整生成。共743步，最后24个完整宏步通过最终检查；源SHA为`990109f4…6d92`，与独立GenericStraightWB运行一致。测试确认各生成阶段、唯一完成事件、完成步数与真实结果相符、进度不倒退、返回后没有迟到进度，且源纸样未改写；输出、证明、指标及含人体OBJ保存。交付SHA256为`3e865adcc9fce5928cb89961b4851258df3d022f487b51b9d30081ddaa8c245b`。这是Mac执行App工作流的组件验收，不是界面操作或手机性能验收。
