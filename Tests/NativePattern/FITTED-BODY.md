# 可选拟合人体工厂与固定表面凭证

`GarmentCodeFittedBody` 把源绑定的拟合草案升级为经过完整静态几何检查的固定人体表面。工厂与默认五尺度人体、旧 Rig／FixedSurfaceReceipt／inverse SDF 分开；它不运行整衣仿真，也不证明动态人体变形路径或26项量体参数全部拟合。

## 捕获和后台准备

主线程可以调用 `captureFit(source:bodyValues:pose:resourceDirectory:limits:isCancelled:)` 捕获原 `StandardBody.Snapshot`、同一完整33参数、明确姿态与四份资源 bytes，得到 `FittingRecipe`。`fitAndPrepare(_:options:limits:isCancelled:)` 必须在后台调用：

1. 用已验证的 `BodySurfaceFitter` 求解四控制／六项固定表面目标。失败携带真实残差和评估次数，不发人体凭证。
2. 只取优化器的四控制量，通过共享 Replay 重新逐位绑定 canonical 来源、重放拟合、重新测量六目标。优化器可解码的顶点、report和布尔都不作为工厂权限。
3. 目标绝对容差固定为 `1e-5m`，不能通过请求选项放宽。按明确 pose policy 重放实际可见表面与同场辅助源点。
4. 完整静态验证器分别检查拟合 rest 与最终表面。只有两份实际网格逐位相同才可核验并复用同一静态证书。
5. 用最终真实顶点／完整原三角面构造 `BodyMesh(signedDistance:nil)`，再构造同一mesh的 `BodyMeshQueries.Prepared`。闭合、面方向、组件体积、顶点面扇与实际BVH检查不会被静态无自交证书代替。
6. 核对最终验证证书、实际mesh、Q索引、Replay最终 SHA、原source映射和完整triangle IDs，完成实际表面点Q查询。全部通过且未取消后才创建 private initializer `SurfaceReceipt`。

固定控制量审计可用 `capture(source:bodyValues:controls:pose:resourceDirectory:...) -> Recipe`、`recipe(...resources:)` 和 `prepare(_:)`。资源已捕获时可用 `fittingRecipe(...resources:)`，不会再次读取文件。`Prepared` 只包含新表面、Q、测量／完整几何报告与拟合摘要，没有旧 Snapshot／SDF；只有未验证的 `FittingRecipe` 私有保留优化器需要的原Snapshot类型。

## 姿态角色与验证接口

`PosePolicy.fittedReference` 是拟合参考姿势，`matchesPatternReference=false`。`matchPatternReference(alphaDegrees:)` 必须逐位等于同33参数里的 `arm_pose_angle`，最终 Replay metadata 也再次核验；不能用30°诊断人体替代45.483°裁片参考。

`SurfaceReceipt` 不可 Decodable，私有构造不接受通用 `isValidated` 开口。公开只读的 `Bindings` 是诊断数据，不能单独变成人体权限。它绑定：

- template／rig／量法／辅助权重资源 SHA 和原 MHW SHA；
- 完整33参数、原canonical geometry／parameter SHA、四控制和fit recipe；
- fitted rest／pose recipe／最终geometry SHA；
- 原可见到source映射及完整triangle IDs摘要；
- 实际目标残差、固定容差及姿态角色。

`surface.verify(positions:triangleIndices:bodyValues:requirePatternReference:isCancelled:)` 逐位匹配真实最终网格，核对完整参数和资源，并消费完整静态证书。默认 `requirePatternReference=true`，参考姿势不能冒充裁片摆姿。`surface.verify(recipe:isCancelled:)` 进一步严格核对原请求的资源bytes、controls、pose、完整参数和canonical坐标。

表面坐标相同不等于来源类型相同。零controls／identity若确实达到其项目目标，仍返回新类型且 `compatibleWithLegacyInverseSDF=false`，不会携带旧SDF／proxy fallback。

## 预算和原子取消

四份资源每文件上限分别为8MB／8MB／2MB／1MB，总捕获默认24MiB。文件按最多64KiB分段读取，最多读取上限加1字节就拒绝，随后复制为自有bytes，避免文件增长或外部no-copy buffer绕过捕获预算。

准备还限制原点数／面数、完整验证候选／BVH／谓词／精确word工作量、Q节点和查询预算。默认256MiB为资源、重放、优化、完整验证与查询的保守工作区预留，不是整个进程RSS硬限制。候选过多、精确谓词超预算、查询未完成都不会发receipt。

取消检查覆盖捕获、优化、重放、完整验证、查询与最终发布。后台API拒绝主线程重工作。nearest舍入检查会锁存回调造成的首个环境变化，拒绝发布；工厂不擅自修改调用者浮点环境。iOS必须链接真实Native C FPU桥。

## 实际验证范围

本轮真实 default／female 的 `fitAndPrepare` 均28次目标评估，重新重放后的最大尺寸残差为 `2.342e-9m`／`5.133e-9m`。两份 fitted rest SHA 与此前独立拟合输出相同。实际 `arm_pose_angle` 参考摆姿后，最终表面各26756原面／13380原点，完整静态候选数177398／177033，并建立了同一mesh的Q；实际表面／内部／外部查询均完成。

控制包含资源／controls／姿态／未使用参数／坐标／面编号篡改，未达到六目标，资源／内存／优化／完整表面／Q预算，立即／中途／最终发布取消，回调改变舍入，identity无旧权限和主线程重工作拒绝。独立Python另对实际输出做完整Fraction闭三角形审计和六项rest长度复算；实际共享simplex只豁免自身，不跳过整个相邻面。

```sh
python3 Tests/NativePattern/run-fitted-body.py \
  --package-proof /path/to/sealed-native-proof
```

Runner冻结15个生产模型和真实资源，执行Mac严格编译／实际后台工厂，跨文件私有构造和Decodable编译负控，两SDK真实最终链接，以及两份独立最终表面审计。SDK链接使用已有sealed Native129 archives和真实C FPU桥，仅从绑定的Swift源发接口；没有重编C++或重跑旧Native套件，也没有安装／运行这些SDK二进制。

此凭证可供后续显式fitted分支接入。装配仍须核对同一纸样的33参数、同一最终mesh和recipe缓存键；该模块的静态人体成功不表示整衣缝合／重力／动态验收已经通过。
