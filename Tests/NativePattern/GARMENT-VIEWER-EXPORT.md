# 独立通用衣服预览与 OBJ

两模块均不启动仿真，也不判断某个诊断 candidate 已成为成衣。宿主仍负责完整
物理验收、原始 source trace、三档实验材料配置、运行状态机和正式入口。
旧 `GarmentCodeDrapeView`、路由、K.Output 与其 `objString` 没有修改。

`GarmentCodeGarmentScene` 是 iOS17 SceneKit `UIViewRepresentable`，输入为
不可变 `output/meshID`，配置支持 yaw/pitch/zoomScale、可见物/衣服聚焦、人台与
接缝开关。`panelNames` 可使用现有中文 Localization；`seamGroupIDs` 是每条
seamPath 的显式源 stitch ID，配对路径传相同 ID 即同色。nil 保留旧橙色，
不猜测任意旧数据的接缝配对。完整 `validatedPanelGroups` 按每片原始节点局部
remap，保证总节点不膨胀成“面板数×全局节点数”；缺少可选分组的legacy数据
保持单个整体网格。有分组但不完整时拒绝，不能丢片。缝线使用批量 line geometry，
不为每个小线段创建一个3D实体。

纯 `GarmentCodeDrapeFraming` 使用完整 xyz 包围框中心与旋转后8角点，按真实
横纵 FOV 和前后深度求相机距离，支持宽袖、帽高、裤腿和偏斜裙。默认缩放
及缩小时完整容纳所选边界；用户放大可主动裁切。衣服聚焦且显示人台时，相机
仍在完整人台边界外。Float 转换、法线、局部索引与 overlay 缓冲在 detached
任务中准备；SceneKit对象与UIView只在MainActor创建。meshID取消/替换与失败
回调隔离；宿主每次改变几何必须更新meshID。未进行 UI 或实机视觉验收。

`GarmentCodeMeshExport.export(output:resultID:directory:limits:isCancelled:)`
是非隔离 async API，内部独立后台任务原字节调用 `output.objString`。返回
`Artifact(resultID,exportID,url,byteCount,sha256)`，同一结果重导产生独立URL，
字节与哈希一致，不需要重跑仿真。写64KiB临时块并同步、关闭后同目录提交；
失败/取消清理本次临时或已提交但尚未返回的文件，不影响另一重导产物。
`remove(artifact)`只清理该已返回文件。默认64MiB上限，原serializer执行期间
不可逐元素抢占，但其前后均检查取消，且预先由顶点/面数及字节预算界定。
宿主仍需用返回resultID匹配当前结果，防止旧导出回调覆盖新 ShareLink。

运行 `Tests/NativePattern/run-garment-viewer-export.sh`：1008组纯相机/frustum
控制、非法数值、独立OBJ V/F/groups/人体索引读回、原字节与legacy对照、并发
同结果重导、Task/晚取消原子清理、预算和IO失败。测试为合成序列化fixture，
不代表物理通过。iOS17 arm64与x86_64 Simulator的完整Swift/SceneKit async
service最终链接另有冻结证据；链接不等于运行界面。

静态接入审查另保留在 `/private/tmp/TailorAss3DUIReadOnlyAudit.md`。尤其注意：
当前 NativeAssembly.prepare 与 JointSimulation.prepare 仍在 MainActor。
最小安全worker边界为已验证 Sendable PreparedInput+body/cloth proofs，可先
将后续数值 JointInput/objective/BVH/独立表面检查移到串行worker；2D源几何和
mesher当前actor限制不会仅靠Task.detached消失。若进一步移动mesher，应局部
提取解析数字curve snapshot，保持精度/189旧mesh字节，不重标全2D内核。
