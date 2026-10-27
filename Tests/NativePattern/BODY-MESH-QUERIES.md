# 可见人体网格的距离与内外查询

GarmentCodeBodyMeshQueries 查询同一份可见闭合三角网格，不经过 1cm SDF 的插值或逆变换。它是数值几何查询；不修改人体/布料，不替代 CCD、接触势、稳定性或体型适配。

## API

~~~swift
typealias Q = GarmentCodeBodyMeshQueries
let mesh = try GarmentCodeBodySurfaceContact.BodyMesh(
    positions: visiblePositions, triangleIndices: visibleTriangles)
let field = try Q.Prepared(body: mesh)
// 或 try Q.Prepared(positions: ..., triangleIndices: ...)

precondition(field.geometrySHA256 == displayedBodyGeometrySHA256)
let r = field.query(point, isCancelled: { token.isCancelled })

switch r.classification {
case .inside:
    // r.signedDistanceMeters is negative.
    // Keep the existing <3mm penetration acceptance threshold.
    break
case .outside, .onSurface:
    break
case .uncertain:
    // Never treat unknown/partial/cancelled work as outside or zero penetration.
    break
}
~~~

Prepared 是不可变 Sendable 值。原始 constructor 先调用已有 BodyMesh 的闭合/一致方向/组件体积校验，再拒绝孤立顶点和仅在一个顶点拼接的分离面扇。未修改旧 BodyMesh、StandardBody、SDF 或资源。输入并不因此获得“人体没有任意非邻面自交”的新证明；内外定义是闭合表面的 even-odd 填充，多层壳按奇偶规则处理。

geometrySHA256 使用现有 rigid-clearance-visible-body-v1 的同一 bytes 格式：前缀、顶点/索引数、原坐标 Double bitPattern 和 UInt32 索引，均 little-endian。不会重新拟合或重新定向可见几何；同一渲染/CCD/势输入必须逐值对应此 SHA。

## 距离与符号

最近距离采用三角 BVH；每个候选取三条边和可行面内投影。BVH 剪枝的上界来自源三角形上真实可行点的向外舍入距离，AABB 下界也向外处理。返回最近距离是 binary64 数值估计，不宣称通用严格误差区间；长期独立全扫 oracle 验证其实际精度。

符号另外做多方向 ray parity。三角命中采用基本算术 nextDown/nextUp 的向外区间 Möller–Trumbore 谓词；只有严格位于面内、正时间的完整交点才计数。边/顶点/近平行/算术不明会废弃整个方向，改用下一固定方向；不猜测重复命中，也不丢弃一个候选来凑奇偶。默认最多 12 个方向，需 3 个无歧义完整方向一致。实际观察到分歧立即 uncertain。

默认 onSurface 容差带为 1e−8m，是显式数值边界带，signedDistanceMeters 返回零；不是衣物壳厚或新增物理余量。可设范围 1e−12…1e−5m。outside/inside 返回正/负 unsignedDistance；uncertain 一律 signed=nil。nearest 搜索尚未完成时，unsigned/closestPoint/triangleID 都为 nil；nearest 完成但 parity 失败时保留 unsigned，仍不给符号。Result 的 signedDistanceMeters 是 computed 属性，持久报告需按需显式编码。

所有路径均有 prepare/query 数量预算、节点/三角形计数及取消检查。预算不足、取消、坏输入、浮点环境不支持均不返回安全结论。Options 可将预算设为零以验证失败关闭。Prepared 限制最多 100k 顶点、200k 三角形、100k BVH 节点；临时存储受这些计数和有限排序树深度约束，不把数组大小报告当作整个进程 RSS。

区间算术要求 nearest rounding；macOS 只读检查 Darwin，iOS/Simulator 使用 NativeClothCollision.FloatingPointEnvironment 的 C 桥；不能导入桥时返回 unsupportedRounding。模块不改变调用线程的浮点环境。

## 长期验证

在仓库根目录运行：

~~~sh
python3 Tests/NativePattern/run-body-mesh-queries.py
~~~

runner 先复制全部实际依赖/资源/fixtures 至唯一 /private/tmp，再以 Release、Swift5、MainActor 默认隔离、complete concurrency 和 warnings-as-errors 编译，保存原始 SHA、命令、日志及 JSON。不安装、不启动 App。包含：

- cube 的解析距离/内外、face/edge/vertex、特征射线换向、不足方向 unknown。
- 球面细分三角网格的解析内切/外接边界和独立全扫；不会把光滑球的半径距离冒充离散网格距离。
- 刚体变换、反向 winding、分离闭合组件、薄 tetrahedron。
- 开口/坏索引/NaN/退化/孤立点/非流形面扇拒绝。
- 准备和查询预算、确定取消、非 nearest rounding 拒绝。
- 默认、官方女性及 26 项各正负扰动，共 54 个实际 StandardBody profile。
- 默认/女性全部 26,760 个可见顶点，包含原 SDF 所有误差点：实际源顶点的精确几何距离为零。
- 540 个独立 full-scan Ericson 距离与 generalized-solid-angle 内外 oracle。法向偏移仅生成候选，其符号仍由独立 oracle 判断，不能直接假定正/负法向就是外/内。
- 小 fixture 绑定原资源 SHA 和最差 SDF 点；JSON 坐标仅容许 1e−14m 的序列化末位差，实际查询使用绑定 ID 的精确源顶点。

跨 SDK 链接另运行（package-artifacts 是显式提供的一次完整 Package 检查产物）：

~~~sh
python3 NativeClothCollision/Scripts/run-checks.py --output /private/tmp/ClothPackageProof
python3 Tests/NativePattern/run-body-mesh-platforms.py --package-artifacts /private/tmp/ClothPackageProof
~~~

第二个 runner 不依赖固定 /tmp 历史路径，独立快照 App 源，记录静态库/模块/header SHA。真实 arm64 iOS17 与 x86_64 Simulator17 Swift 静态链接后，用 vtool 核对平台/minimum OS，用 nm 验证实际浮点 C 桥符号。这里只链接，不把设备二进制当作已运行的物理验收。

## 使用边界

旧粗 SDF 可继续作为诊断；独立胸颈/四肢拟合后不得复用其旧逆映射来声称同源精度。人体最终验收应让此 field、渲染、CCD、势都绑定同一最终网格。此模块不改变既有 3mm 穿入阈值，也不表示 26 项人体适配或完整成衣求解已经完成。

