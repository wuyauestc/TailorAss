# 拟合人体的完整静态表面验证

`GarmentCodeBodySurfaceValidator`只证明传入的同一份三角面集合没有超出真实拓扑共有点／边的交集。它不证明闭合、流形、朝向、人体量法、合身或连续摆臂。新拟合人体工厂仍须另外通过`BodyMesh`、`BodyMeshQueries`及其同一geometry SHA约束；不能复用旧五尺度inverse SDF。

## 来源与凭证

`validate(positions:triangleIndices:limits:isCancelled:)`完成所有实际候选后才返回`Certificate`。其构造器为fileprivate，不支持Decodable；`Report`是可编码的数据，不能用布尔或调用方SHA换取能力。证书私存完整原数组，`verify`核对全部三角ID和每个坐标的Float64位模式，包含正负零。geometry SHA沿用`rigid-clearance-visible-body-v1\0`、两个UInt64LE长度、xyz位模式和UInt32LE索引的原约定。

## 完整几何判据

BVH对原始有限坐标取inclusive min/max，查询所有三角对且仅保留`j>i`，因此精确边界接触不会被宽相位删除。不按共享顶点跳过整对三角面。

所有符号首先用向外舍入区间证明。跨零、下溢或溢出的区间回落到原Float64坐标的精确有理符号：将每一坐标表示为带符号整数乘同一二次幂，只用有界base2^32整数加减乘计算二维／三维行列式。没有近零epsilon、交点采样、浮点除法或舍入后的交点坐标作为精确证明。

- 共有一条真实边：非共面时两面所在平面仅交于该边；共面时必须分处该边两侧。同侧折叠拒绝。
- 共有一个真实点：只有两非共有点严格处于另一面同侧时才可提前证明交集仅为共有点；否则仍检查所有闭边／闭面事件。
- 一般非共面：检查双向全部边与闭三角面的交集；平面内的边继续做精确二维闭交集检查。
- 共面：检查所有非共有顶点的闭包含及所有边的严格横交。凸三角形若有其他点／线／面积交集，必有非共有端点闭包含或严格边横交；真实共有simplex之外的接触均拒绝。
- 重复面、精确退化、非拓扑点／边接触一律拒绝。真实ID不同而坐标相同不会获得邻接豁免。

BVH、候选对、谓词、整数逐字操作、整数容量与保守工作内存均有有限上限。每次取消回调后和发布前检查最近舍入；取消、错误舍入和任何预算失败都不会返回证书。内存数字是明确的保守数组／索引／算术暂存估计，不是进程RSS测量。

## 可复现专项

运行`Tests/NativePattern/run-body-surface-validator.py`；传`--native-proof /private/tmp/TailorAssFSCCriticalIntegratedSecond`可复用封存129的原C++归档，只重新编译Swift接口和实际消费者，完成iOS17 arm64、Simulator x86_64最终静态链接，不重编C++。

专项包含共有点额外交叉、共有边共面折叠、非拓扑接触、共面分离、极端尺度／平移／方向、精确退化、预算、取消、发布前取消、舍入模式和证书篡改。原`ExactBodySurfaceGeometry.py`中纯Fraction函数的AST保持不变独立运行；以运行时hex位模式绑定同一坐标，避免不同JSON解析器产生末位差。

六份default/female × 30°/45°/60°网格从真实Replay和固定四参数重新生成。每份完整geometry SHA、inclusive候选数及合法拓扑touch数与此前独立Fraction全对参考逐项一致。参考来源与原文件SHA位于`Fixtures/body-surface-validator/manifest.json`。六固定参考仅是回归样例；运行时仍完整检查每一份新输入，不能据这些案例给任意拟合参数通行凭证。

## 本轮实证

`/private/tmp/TailorAssBodySurfaceValidatorActualSecond`完成13个生产模型的Swift5/MainActor/complete concurrency/warnings-as-errors编译、100解析控制、17拒绝控制、259个hex绑定Fraction对照和六完整人体检查。每个人体26756面，inclusive候选176289–177374对，合法真实拓扑touch均161820对，其余严格分离；单份验证约0.3秒，保守工作内存约22.2MB。两SDK客户端均实际最终链接成功。

这些是模块专项，不能冒充新完整App构建、任意人体姿态的连续路径或整衣最终验收。本轮未改变旧CCD、Native129、标准人体、S/R/N或默认路由。
