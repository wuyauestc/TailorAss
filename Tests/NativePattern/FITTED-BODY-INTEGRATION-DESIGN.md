# 拟合人体的来源验证与装配接入

当前已实现显式选择的拟合人体工厂与完整裁片装配路径，默认人体及正在运行的旧来源整衣仿真保持原样。`FitDeformationReplay`本身仍只输出形变／姿态数据；只有新的`FittedBody`工厂实际重放、复测和完成几何验证后，才创建当前实际表面凭证。

## 当前实现和验证

- `Settings.bodyShapeSelection = .surfaceMeasurements`需同时选择`.matchPatternReference`。主线程只捕获原人体参数和四份有界资源字节，worker执行优化，再独立重放实际controls、复测六项表面目标。目标误差上限保持10微米；它不是全部26项参数的独立人体拟合。
- 新的完整静态表面验证器检查所有可能接触的三角面对，只允许真实共享顶点／边的拓扑接触。拟合原姿和最终摆臂表面都通过才发布；不证明人体摆姿动画的扫掠路径。
- `AssemblyBuilder`以互斥enum保存标准、参考摆臂、拟合三种来源。`SewnInput`将拟合凭证核对到同一完整纸样的33个原始／派生人体参数；可见mesh、避让、BodyMesh、精确Q查询和联立目标使用同一实际表面，旧SDF及旧投影器不能接收拟合人体。
- `JointWorkflow.generate`提供显式body-shape选择，结果标为项目表面尺寸拟合／参考摆臂人台。App默认入口尚未启用；没有创建新的成衣成功输出。

四组真实装配为default／female × 圆裙加腰头／带袖衬衫，每组均保留全部源rest、面积质量与零固定点，并通过初态接触及完整联立能量检查，合计32项否定／取消控制。旧人体另通过12个完整状态字节对照、16组摆臂装配和134项原控制。组合交付为`/private/tmp/TailorAssFittedAssemblyIntegrationDelivery/delivery-manifest.json`，SHA256 `3ba7b96426a72f0432929a6c7c94dc374744d1893f24e93c15d7a8c934af94f4`。

新50模型严格联编后，两款真实拟合人体的首个静态配置步通过S与R fresh受力／当前P修正／完整源和碰撞路径复核，57项数据控制通过；未跑拟合人体整衣动态验收。证据为`/private/tmp/TailorAssFittedJointControls/delivery-manifest.json`，SHA256 `2c20d52ac71f0ee2f5e5fa1a136876261cc09b76d29194fd83dd31bc8fc22415`。可用`run-joint-result.py --body-shape surfaceMeasurements --body-pose matchPatternReference`显式选择，记录另存人体选择与来源绑定，默认参数保持旧来源。

工厂与两平台链接的独立交付为`/private/tmp/TailorAssFittedBodyFactorySealed-w4jwrf88/delivery-manifest.json`，SHA256 `289b10b36f7d6ea13f5b946890b1c69e7583ef2dcae5f8c5e326a2e731e70946`。以下保留设计约束；实际是否通过以上述有界证据为准，不推导全款式、真机性能或个体合身。

前一阶段先以legacy／posed枚举替换两个可选值及`posed ?? legacy!`强制解包，其独立回归保留在`/private/tmp/TailorAssBodyReceiptEnum/`，SHA256 `d6c5126eef8dbebc2d6769ea31a510774a5d9807a73628bc5cb8643679cd99ca`。此历史记录不包含后来加入的fitted分支，不能代替上面的新整合验证。

## 已具备的共同来源

纯Replay把相同四阶段场用于13380可见点和1117辅助CC0源点；135重合点逐位一致，后取326组原始引用均值。新辅助权重资源保留原MHW来源，全部982隐藏点有原权重，不需要近邻猜测。visible变形与原优化器逐位相同。

ShapeData保留全部33参数、source geometry／parameter SHA、template／rig／量法／辅助原权重资源SHA、controls及fit recipe和实际geometry SHA。PoseData另有pose recipe SHA、请求角和是否等于输入arm_pose_angle；它的骨架frame代理与LBS辅助均值明确区分。所有数据始终不兼容旧inverse SDF、不发body capability。新consumer只通过Context.deform使用统一核；不得从可解码Attempt直接发布人体。

## 最小新增工厂

建议新增独立`GarmentCodeFittedBody`，不扩张旧`GarmentCodeFixedBody`的语义：

- `Recipe`：原template／rig／aux／量法bytes或严格绑定的资源引用、全部33目标参数、固定controls、pose policy。它是请求数据，不能靠claimedSHA或布尔表示已验证。
- `prepare(recipe:)`：worker重新生成原五尺度reference，调用Replay.context/deform；重测6个项目表面目标；根据明确pose policy生成实际表面。`matchPatternReference`必须要求请求alpha与同一33参数的arm_pose_angle逐位相同，不能把诊断30°表面配给45°裁片。
- `Prepared`：同一实际mesh、精确Q查询、private-initializer `SurfaceReceipt`及独立完整几何报告。receipt仅由真实重放和几何验证成功后构造，不提供Decodable或任意数组／isValidated初始化器。

`SurfaceReceipt`至少绑定template/rig/aux/量法版本、原MHW SHA、33参数SHA、fit recipe、fitted rest geometry、pose recipe和最终geometry、原visible/source映射与完整triangle IDs。verify应检查实际positions/triangles和私有来源，而不只接受调用者重新计算的一份SHA。

即便controls全零／identity恰好与旧mesh相同，这种新类型也不携带旧Snapshot或SDF权限，避免特殊分支再次混用。

## 必须补齐的运行时几何门槛

BodyMesh构造已检查闭合、同向边使用、非退化和组件体积，并能在不传SDF closure的情况下工作；Q.Prepared提供同一mesh的实际最近距离／内外查询。二者的SHA一致是来源绑定，**不是**完整无自交证明。

旧Rig和ClothContact.inspect的共享顶点整面对排除不覆盖所有相邻折叠；VisibleBodyInspection中的严格SAT是两份不同表面的严格分离，不能直接拿body对自身调用（合法共享边／点必然接触）。新工厂须有完整的self-surface检查，只允许真实拓扑共享simplex，任何超出共享点／边的proper/coplanar交叠都拒绝；预算、不确定和取消不能发receipt。

已有六个default/female×30/45/60案例由独立Fraction全对检查证明静态无交叉，但它只覆盖这六个实际最终网格，不是任意参数的运行时能力或动态人体动画路径。需要同一实际网格的原生完整验证器后，才进入正式显示／碰撞链。

## 未来最小调用接缝

1. **NativeAssembly.capture**：仍校验完整body/design与重生成paper SHA，保留所有源裁片／接缝。新增显式fitted body recipe选择，默认仍走现有Builder.captureBody。拟合目标必须来自此处同一body.values，不允许单独改人体目标以掩盖裁片问题。
2. **Builder BodyReceipt/ResolvedBodyReceipt**：增加独立的新fitted分支或有穷enum，避免现有`posed ?? legacy!`在第三种状态下出错。MainActor只捕获原参数／资源，重放、拟合、几何与BVH在worker。原Snapshot可以作为reference来源，但不得进入新结果的standardBody。
3. **NativeAssembly.build**：刚体人体避让使用新receipt.mesh；Builder.prepare把同一positions/triangles写入mannequin显示与bodySurfaceMesh。全源SHA、rest、mass和源缝合不变。
4. **Kernel.Input / attachBodySurfaceContact**：旧standardBody、旧fixedBodySurface、新fittedSurface三种状态严格互斥。新分支要求standardBody=nil、旧fixedReceipt=nil；mesh从新receipt取得，`BodyMesh(..., signedDistance:nil)`。不能给旧FixedSurfaceReceipt换顶点，也不降级为proxy圆台。
5. **SewnInput.prepare**：新分支验证完整fitted receipt、同一可见mesh／body mesh及原source来源。现有二分支会正确拒绝新mesh，不能绕过它。旧Circle/XPBD入口显式拒绝新类型，即便pose identity或设置仍是legacyTemplate，也不得回退旧逆SDF。
6. **Joint body objective / CCD / final Q**：都只消费此同一实际固定mesh。刚体避让proof、body势、CBC、最终VisibleBodyInspection／exact Q和显示geometry SHA必须一致。S/R/N的力学与门槛无需为人体拟合改变；仅新body准备来源需要通过入口。
7. **输出与缓存**：bodyModel明确标项目表面目标拟合／参考摆臂，不标个体扫描或26项全部拟合。缓存键加入fit recipe／pose recipe／最终body SHA及资源版本；旧body BVH／SDF／prepared cloth不能按相同paper SHA复用。

轻量receipt与重工厂的Swift访问级别要实测：跨文件不能伪装调用private/fileprivate init。可让新工厂与新receipt放同一新文件；若Kernel显式存该类型，旧小型runner须显式加入新依赖，不用协议可随意实现的`isValidated`绕过验证。

## 接入前控制

- 同源default/female reference/拟合/pose分别重放，原135点与所有索引／权重保留；旧源与SDF资源SHA不变。
- 参数、controls、量法、template/rig/aux、pose angle、geometry、source mapping任一篡改皆拒绝。
- 旧Rig.pose与旧FixedSurfaceReceipt确实拒绝拟合网格；新分支没有旧SDF／proxy fallback。
- 原子取消、有限几何／内外／资源预算；相邻面真实折叠、coplanar重叠和不可判均不发新receipt。
- 同一mesh的display、BodyMesh、Q、clearance、IPC、CBC与最终proof逐SHA核对。默认legacy准备及原App行为另做逐位回归。
- 先仅新body准备／新SDK真实链接，不在这里启动整衣仿真或把静态人体检查当成衣通过。
