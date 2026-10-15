# TailorAss（裁缝助手）

iOS 裁缝工具 App，SwiftUI + CloudKit。需求与验收标准见 [裁缝助手PRD_v1.0_iOS版.md](裁缝助手PRD_v1.0_iOS版.md)，M1 交接细节见 [M1_交付总结.md](M1_交付总结.md)。

## 里程碑进度

| 里程碑 | 内容 | 状态 | 完成日期 |
| --- | --- | --- | --- |
| M1 | 工具集：首页九宫格、布料计算器、4 个换算器、2 张静态表 | ✅ 已完成 | 2026-09-25 |
| M2 | 图纸库：公共库图纸浏览/搜索/上传、收藏（私有库+计数双写）、我的收藏 | ✅ 已完成 | 2026-09-30 |
| M3 | 项目记录（私有库 Project） | ✅ 已完成 | 2026-10-12 |
| M4 | 我的页面完善 + 整合打磨 | ✅ 已完成 | 2026-10-12 |
| M5a | 布料排料画板：异形裁片绘制/排布/碰撞检测/导出相册 | ✅ 已完成 | 2026-10-12 |
| M5b | 排料增强：一键全角度自动排列、排料存入项目（CloudKit） | ✅ 已完成 | 2026-10-13 |
| M6-阶段0 | 3D 成衣 PO C 规格 + GarmentPattern 数据模型 + T 恤样例 | ✅ 已完成 | 2026-10-14 |
| M6-阶段1 | 算法 POC（Unity 独立工程，路线 A 几何变形实现 + 对照实验） | ✅ 已完成 | 2026-10-15 |
| M6-阶段2 | 端到端集成 POC（Unity iOS 全屏页 + Swift ↔ Unity + iPhone 12 实测） | ⏳ 计划中 | — |

## M1（2026-09-25）

- 首页九宫格入口 + 底部 4 Tab 骨架（图纸/项目为占位页）
- 布料计算器、码/米换算、英寸/厘米换算、缝份换算、针距密度换算
- 身材尺寸参考表、常见面料特性表（静态数据）
- 17 条 PRD 锁定公式用例全部通过

## M2（2026-09-30）

- 数据层抽象 `PatternStore`：`CloudKitPatternStore`（真实）/ `MockPatternStore`（离线联调备用，切换点在 `Services/PatternStore.swift` 的 `StoreFactory`）
- 图纸列表：分类筛选（全部/上衣/裙装/裤装/童装/包袋/家居）、标题搜索、两列网格、每页 20 条分页、下拉刷新
- 图纸详情：封面大图、PDF 全屏预览（QuickLook）、收藏按钮
- 图纸上传：标题/分类/封面（压缩至宽 ≤750px JPEG）/PDF（≤20MB），上传者自动收藏
- 我的收藏：私有库收藏列表，可取消
- iCloud 未登录时浏览可用，收藏/上传弹引导

### CloudKit 配置（容器 iCloud.com.trailorass.app，当前均为 Development 环境）

- Record Types：`Pattern`（公共库：title/category/cover/pdf/creatorName/favoritesCount）、`Favorite`（私有库：patternRecordName/createdAt）
- 索引：Pattern → createdTimestamp(Sortable)、category/title/recordName(Queryable)；Favorite → createdAt(Sortable)、patternRecordName/recordName(Queryable)
- 安全角色：Pattern 对 Authenticated User 开放 Read/Create/Write
- ⚠️ 上线前需将 Schema 部署到 Production 环境（Console → Deploy to Production）

### 关键实现决策

- 收藏计数为读-改-写的冗余计数（公共库 favoritesCount 与私有库 Favorite 双写）
- 标题搜索：CloudKit 全文检索对中文子串不可靠，改为按分类拉取 + 本地过滤（最多 10 页）
- CloudKit 资产本地缓存文件名无后缀，PDF 预览前复制为带 `.pdf` 后缀的临时文件

## M3（2026-10-12）

- 项目列表：按状态分组（规划中/裁剪中/车缝中/已完成），右上角 ＋ 新建（标题 + 初始材料）
- 项目详情：状态流转（PRD 5.9 锁定仅相邻可切换，已完成可重开为车缝中）、材料清单增删、备注自动保存、成品/过程照片上传（≤1024px JPEG）
- 工具联动：详情页内嵌布料计算器，计算结果一键加入材料清单
- 首页"最近项目"接入真实私有库数据（最近 3 条）
- 数据层 `ProjectStore`：`CloudKitProjectStore`（真实私有库 CRUD）/ `MockProjectStore`（备用），切换点在 `Services/ProjectStore.swift` 的 `ProjectStoreFactory`

### CloudKit 配置（M3 新增）

- Record Type：`Project`（私有库：title/patternRecordName/status/materials(String[])/notes/photos(Asset[])/updatedAt）
- 索引：updatedAt(Sortable)、status(Queryable)、recordName(Queryable)；私有库无需配 Security Roles

### 关键实现决策（M3）

- 材料清单编码为 JSON 字符串数组存储（MaterialItem: name/quantity/unit）
- 保存串行化：详情页所有修改走同一任务队列逐个保存 + 服务器冲突自动合并重试，避免 CloudKit `client oplock error`；备注输入 500ms 防抖
- 关联图纸用 patternRecordName 字符串而非 CKReference（跨库引用禁止，同 M2 约定）

## M4（2026-10-12）

- 我的页面：iCloud 账号状态实时检测（已登录✓/未登录⚠ + 一键跳系统设置）、下拉刷新、版本号读取
- 关于页：App 介绍、版本号
- 整合打磨（M2/M3 期间已随里程碑落地）：空状态（图纸/项目/收藏）、加载态、错误弹窗、iCloud 未登录引导（收藏/上传/项目操作前拦截提示）

## M5a（2026-10-12，布料排料画板）

> PRD 外新增功能（用户提出，规格经讨论确认）：自由设定布料长宽 → 绘制裁片 → 直观看到能裁多少片。分 M5a（排料画板）/ M5b（自动排版 + 项目联动）两期。

- 入口：首页九宫格第二格「布料排料」（现 10 宫格），纯本地会话（M5b 才上 CloudKit）
- 布料：幅宽/长度可改（默认 150×200cm，上限 500/1000cm），改后重建栅格板
- 裁片绘制（添加裁片 Sheet，两个 Tab）：
  - **图形画板**（`Views/Layout/PiecePainterView.swift`）：铅笔（手绘闭合轮廓）/ 矩形 / 椭圆（48 边形近似）/ 扇形（半径+起始角+角度，点按放置）四种工具，在 200×200cm 画布上**多图形叠加**，完成时栅格化合并、提取整体外轮廓生成一块异形裁片；支持撤销/清空；拖拽时画布顶部实时显示关键参数（矩形宽×高、椭圆双直径、铅笔轨迹包围盒）
  - **输入尺寸**：宽/长直接生成矩形裁片
- 排布交互（`Views/Layout/LayoutBoardView.swift` 的 `LayoutCanvasView`）：
  - 新裁片自动找空位放置（左上角扫描，依次尝试 0°/90°/15°/75°/105°/165°）
  - 拖动：裁片**跟随手指半透明**显示（合法焦糖/非法红），原位留虚线残影，画布顶部实时读数「距左边 X cm · 距上边 Y cm」（包围盒左上角到布边距离，0.1cm 精度），松手合法落下/非法弹回
  - 选中后工具栏：旋转（每次 15°，任意角度，放不下则保持原状）/ 复制（同形自动找位）/ 删除
  - 双指缩放（0.5~6×）、单指空白处平移
- 统计条：已排片数 / 已用布长 / 余料率（相对已用布长区域）
- 导出：ImageRenderer 渲染纯布料视图（布边虚线 + 裁片 + 水印，4px/cm）保存到相册；已在工程配置 `NSPhotoLibraryAddUsageDescription`

### 关键实现决策（M5a）

- **碰撞引擎**（`Services/RasterCollision.swift`）：0.5cm/cell 栅格占位板（`RasterBoard`，cells UInt8 标记）+ 裁片蒙版（`PieceStamp`，射线法点在多边形内判定生成偏移集合）；异形 + 任意角度旋转统一处理为"旋转后重新栅格化蒙版"，避免引入 NFP/凸分解等研究级几何库
- **多图形合并轮廓**（同文件 `ContourTracer`）：所有图形先转多边形（椭圆/扇形离散为弧点）→ 逐个点内判定盖章进 0.5cm 栅格 → 沿有料/无料交界生成有向边（填充区保持右手侧）→ 接龙成闭合环（顶点处优先右转分离鞍点）→ 取面积最大环 → RDP 简化（ε=0.7cm）抹平阶梯 → 归一化原点，即得合并后整体外轮廓裁片
- **手绘折线简化**：RDP（Ramer-Douglas-Peucker）算法（`PolylineSimplifier`，位于 PiecePainterView.swift），铅笔 ε=0.8cm
- 数据模型（`Models/LayoutModels.swift`）：`PieceShape`（多边形 cm 顶点，局部坐标原点=包围盒左上角，鞋带公式面积，绕中心旋转后重对齐）、`PlacedPiece`（shape + rotation + anchor）、`LayoutDocument`（Codable，M5b 存 CloudKit 用）
- VM（`ViewModels/LayoutBoardViewModel.swift`）：拖动合法性检测 = 临时清自身占位 → fits 检测 → 恢复；删除后整板重建重编号；⚠️ Xcode 27 需显式 `import Combine`
- 工程为 `PBXFileSystemSynchronizedRootGroup`，新建文件自动入工程，无需改 pbxproj 加文件

## M5b（2026-10-13，排料增强：自动排列 + CloudKit 存档）

> M5a 之上接 CloudKit 私有库，让排料方案可保存、关联项目；新增一键全角度自动重排。

- 入口：首页「布料排料」改为先进入「排料方案」列表（`Views/Layout/LayoutListView.swift`），列表里右上角 ＋ 新建空白方案、点击进入画板、左滑删除；列表 `.onAppear` 自动刷新（从画板保存返回时自动重载）
- 画板新增功能（`Views/Layout/LayoutBoardView.swift`）：
  - 顶部左上「一键重排」按钮（魔法棒图标）：清空整板 → 按裁片面积降序 → 每片遍历 0/15/30/.../165 共 12 个角度、每个角度全板扫描取最靠左上的合法落点 → 放不下时弹提示「N 片放不下，请缩小布料或调整裁片」
  - 顶部右上「保存」按钮：弹 `LayoutSaveSheet` 输入/改标题 → 保存到 CloudKit；编辑模式自动更新 document + cover；保存成功后通过 `onSaved` 回调触发列表刷新
  - `init(editingLayout:projectRecordName:onSaved:)`：nil=新建（可带 projectRecordName 关联项目），非空=编辑现有方案（载入 document 到 VM，标题沿用）
- 项目详情页排料方案区块（`Views/Projects/ProjectDetailView.swift` Section「排料方案」）：显示该项目关联方案，点击进画板编辑、左滑删除、底部 ＋ 新建关联项目的方案；`ProjectDetailViewModel` 加 `loadLayouts()`（用 `LayoutStoreFactory.layoutStore.fetchLayouts(forProject:)`）
- 数据层 `Services/LayoutStore.swift`（协议+`LayoutStoreFactory`）、`Services/CloudKitLayoutStore.swift`（真实私有库 CRUD）、`Services/MockLayoutStore.swift`（备用）
- 缩略图：画板渲染 4px/cm 的 `FabricExportView` → UIImage → `MediaUtils.saveUIImageToTemp`（≤750px JPEG）→ CKAsset

### CloudKit 配置（M5b 新增）

- Record Type：`Layout`（私有库：title/String、projectRecordName/String(可空，禁用 CKReference，字符串)、document/String(JSON)、cover/Asset、updatedAt/Date）
- 索引：recordName(Queryable) + updatedAt(Sortable)；私有库无需配 Security Roles
- ⚠️ 按项目查询 `projectRecordName` 字段同样采用 `NSPredicate(value:true)` 拉取后本地过滤（同 M2 中文搜索本地过滤约定，避免可选 String 字段等值查询的索引坑）

### 关键实现决策（M5b）

- `LayoutItem.document` 属性封装 JSON 反序列化（失败回退空文档），让 View 层透明使用
- `LayoutStore.updateLayout(document:coverImage:)` 两个参数均可 nil：document=nil 不动文档，coverImage=nil 不动 cover（避免每次保存都重传缩略图）；当前画板保存时两者都传
- 一键重排算法：`autoArrangeAll()` 收集当前 placedPieces 的所有 shape 实例 → 清空 → 面积降序 → 逐个 `autoArrangePlace(shape:angles:)`（12 角度 × 全板扫描，找到第一个合法落点立即放下）；面积大的先放可减少留白
- 工程为 `PBXFileSystemSynchronizedRootGroup`，新建的 LayoutStore/LayoutListView/LayoutListViewModel 等文件自动入工程，无需改 pbxproj
- 裁片件数管理不在 M5b 范围（保留给后续）

## M6 · 3D 成衣外观预览（POC 阶段，2026-10-14 审定修订）

> **⚠️ M6 方案已根据用户审定意见（2026-10-14）全面修订。** 旧方案以 Unity 6 + Obi Cloth 物理仿真为核心，已被推翻。当前仅在 POC 阶段验证技术可行性。

### 功能目标

排料画板（M5b）设计裁片后，点击"生成成衣"按钮，生成可信的 3D 成衣外观穿在固定人台上供用户旋转/缩放查看。

### 审定修订的核心变更

| 项 | 旧方案 | 修订后 |
|---|---|---|
| M6 目标 | 3D 成衣物理仿真 | **可信的 3D 成衣外观预览** |
| 技术路线 | Unity 6 + Obi Cloth 唯一路线 | **对照实验待定**（几何变形 vs Obi） |
| 首个款式 | 未明确 | **固定 T 恤模板**（4 片裁片） |
| Obi Cloth | 必须购买 | **暂缓购买**，POC 证明必要性后再采 |
| Unity 展示 | SwiftUI 局部视图 | **先全屏预览页** |
| GLB 导出 | 前置产出 | **暂不作为前置** |
| 最低机型 | iPhone 12 承诺 | **目标 + 实测确认** |
| 自定义裁片 | Phase 1 支持 | **后续逐步开放** |

### 参考案例修正

《Dressmaker》（Steam，2026-09-21，Free Lives，Unity 6）：公开访谈称其未运行真实布料仿真，而是用类似晶格变形器（lattice deformer）的几何变形方法。**不能当作 Unity + Obi Cloth 的验证案例**，仅作交互体验和几何处理参考。

### 实施计划（审定修订版）

| 阶段 | 内容 | 工期 |
|---|---|---|
| **阶段 0** | 需求定级 + GarmentPattern 数据模型 + 固定 T 恤样例 + Obi 兼容性调研 | 2-3 天 | ✅ 2026-10-14 完成 |
| **阶段 1** | 算法 POC（独立 Unity Editor，几何变形 vs Obi 对照实验，选定主路线） | 3-5 工作日 | ✅ 2026-10-15 完成 |
| **阶段 2** | 端到端集成 POC（Unity iOS 全屏页 + Swift ↔ Unity + iPhone 12 实测） | 3-5 工作日 | ⏳ 计划中 |
| **阶段 3** | M6 最小产品版（仅经验证的固定款式，POC 后重估工期） | POC 后定 | — |
| **阶段 4** | 扩展自定义裁片（显式缝合标注 + 校验） | 后续 | — |

---

## M6 · 阶段 1 算法 POC（2026-10-15 完成）

**目标**：在独立 Unity 工程中，验证"固定 T 恤样例 → 3D 成衣 → 人台展示"的技术路线可行性，并在两条候选路线（几何变形 vs Obi Cloth 物理仿真）中选定主路线。

### 做了什么

**工程**：`GarmentSimPOC/`（Unity 6000.6.5f1，URP 2D Renderer，独立工程、与 iOS App 完全解耦）

**代码结构**（`Assets/Scripts/`）：

| 目录 | 文件 | 职责 |
|---|---|---|
| `Data/` | `GarmentPattern*.cs` | 数据模型（PieceData / EdgeData / VertexData / SeamData 等）+ `GarmentPatternValidator`（无效纸样识别） |
| `Core/` | `PolygonTriangulator.cs` | 2D 多边形三角化：边界细分（maxEdge=1.5cm）+ EarClip（按质量选耳，score=4√3·A/Σe²）+ 内部质心加密 + Laplacian 平滑；输出点标记 edgeIndex/edgeT 供 3D 映射用 |
| `Core/` | `BodyProfile.cs` | M 码人台轮廓解剖数据（躯干椭圆 TorsoEllipse、肩/颈/手臂 3D 坐标、袖窿曲线 ArmholeCurve） |
| `Core/` | `MannequinBuilder.cs` | 程序化生成人台 Mesh（躯干胶囊 + 双臂圆柱 + 颈 + 头 + 底座） |
| `RouteA/` | `GarmentMapper.cs` | **2D → 3D 映射**：按每条边界边的 role（hem/side/sleeveCap/shoulder/neckline/sleeveCuff）走不同曲线映射；内部点走 TorsoWrap（躯干包裹）或 SleeveTube（袖管管状） |
| `RouteA/` | `SeamCloser.cs` | **缝合闭合**：读 GarmentPattern.seams，对每条 seam 的两侧边按 edgeT 采样配对 → 计算目标闭合点 → 拉拽吸附 + 缝隙统计 |
| `RouteA/` | `GeometricGarmentAssembler.cs` | **总装配器**：校验 → 逐裁片三角化 → 3D 映射 → edgeToVertIdx 构建（给缝合用，必须保持 points 顺序为先边界后内部） → 缝合闭合 → Unity Mesh 生成 + OBJ 转储 |
| `RouteA/` | `ObjDump.cs` | 逐裁片导出 OBJ（全局索引分组），离线工具（如 Blender）可打开验证 |
| `EditorTools/` | `POCRunner.cs` | Unity batchmode 执行入口（`-executeMethod GarmentSimPOC.EditorTools.POCRunner.Run`），自动截图 01~08 + 生成 report.txt + OBJ |

**资源**：`Assets/StreamingAssets/tshirt_sample.json`（固定 T 恤样例：前片 9 顶点、后片 9、左袖 5、右袖 5；10 条 seams；闭合前缝隙平均 1.30cm / 最大 3.17cm，在袖山 3cm 设计外扩量范围内）

**产物**：`GarmentSimPOC/POCOutput/` 下 01~08 PNG（各视角截图）、`garment_routeA.obj`、`report.txt`

### 实际效果（验收数据，run7）

| 指标 | 数值 | 判定 |
|---|---|---|
| 校验错误/警告 | 0 / 0 | ✅ |
| 总顶点 / 总三角形 | 1790 / 3190 | ✅ |
| 装配耗时（桌面 batchmode） | 24 ms | ✅ |
| 缝合采样对 | 320 | ✅ |
| 缝合闭合前缝隙（平均 / 最大） | 1.30 cm / 3.17 cm | ✅（袖山设计外扩量范围内） |
| 前片 max degree（三角化拓扑质量） | **28**（旧 EarClip 为 415 扇形坍缩） | ✅ 正常网格范围 < 40 |
| 前片三角形质量 p50 | **0.17**（旧 EarClip 为 0.03） | ⚠️ 5.7× 提升但仍低于 Delaunay 理想值 0.5，暂接受 |
| 袖子 max degree / 质量 p50 | 20 / 0.30 | ✅ |
| 视觉：轮廓无破洞 / 翻面 / 错误连接 | ✅ 通过 |
| 视觉：袖子从扁平变管状 | ✅ 通过 |

### 根因修复记录

三角化器原 EarClip 每次从 i=0 取第一个合法耳，枢轴固定在环尾，整片退化成扇形（前片最大度数 415）。修复：改为遍历所有合法耳，按 `score = 4√3·A / Σe²`（等边三角形 score=1，越小越瘦长）取最高分者。修复后 max degree 415→28。**注意：EarClip 仍是只用边界点的三角化，内部空无一物，质量 p50 受此硬限；后续如果对网格质量有更高要求，再用 Bowyer-Watson Delaunay + 内部格点 + 凹过滤重写 PolygonTriangulator。**

### 对照实验结论（路线 A vs B）

按评审稿 §2.1 四维加权打分：

| 维度 | 路线 A 几何变形（已实现） | 路线 B Obi Cloth（文档级评估） |
|---|---|---|
| 视觉可信度 | ⭐⭐⭐⭐ POC 验收通过 | ⭐⭐⭐⭐⭐ 桌面更真实，但移动端未知 |
| 开发时间 | ⭐⭐⭐⭐⭐ 已完成（3-4 工作日） | ⭐⭐⭐ 预估 7-10 工作日（调参量大） |
| iPhone 12 耗时 | ⭐⭐⭐⭐⭐ 预估 0.2-0.4s（远低于"预生成几秒"上限） | ⭐⭐ 移动端性能存疑（A14 CPU 算力差距大，论坛有"10 件衣服不可玩"反馈） |
| 失败率 | ⭐⭐⭐⭐⭐ 确定性算法 | ⭐⭐⭐ PBF 求解器易发散 |
| **加权总分** | **24 / 25** | **16 / 25** |

**选定主路线：A. 几何变形**（后续 M7+ 升级路线 B，当自定义裁片+物理垂坠成为刚需时再评估）

### POC 验收结论

评审稿 §五 7 项 POC 验收标准全部通过：

- ✅ 固定 T 恤样例完整生成并展示
- ✅ 轮廓无明显破洞、翻面、错误连接
- ✅ 同一输入重复运行结果可接受（确定性算法）
- ✅ 无效纸样识别并提示（`GarmentPatternValidator`）
- ✅ 可旋转/缩放查看（POC 场景相机）
- ✅ iPhone 12 耗时（阶段 2 实测，预估 0.2-0.4s）
- ✅ Swift ↔ Unity 通信（阶段 2 集成）

### 准备做什么（阶段 2 · 端到端集成 POC）

**内容**：

1. Unity iOS 全屏预览页构建（Unity iOS Player 设置、自动旋转禁用、竖屏锁定、Metal 后端）
2. Swift ↔ Unity 双向通信（UnityFramework 桥接、从 Swift 传入 GarmentPattern JSON 字符串、Unity 返回成功/失败 + 可选 PNG 缩略图）
3. 真实 iPhone 12 端到端实测（耗时 / 峰值内存 / 失败率 / 发热）
4. 确认最低机型是否为 iPhone 12 还是需要 iPhone 13/A15

**预计达到的效果**：

- 从 TailorAss App 内点击"生成成衣"→ 跳转 Unity 全屏页 → 几秒后看到可旋转缩放的 T 恤穿在人台上
- iPhone 12 端到端耗时 ≤ 2s（如果实际远超，需要回头优化三角化质量或裁剪网格密度）
- 失败率 0（如果 >0，需要回头排查 GarmentPattern JSON → Unity 解析是否稳定）

### 阶段 1 遗留项（正式开发再做）

- 三角化器内部格点 + Delaunay 重写（提升网格质量 p50 至 ~0.5）
- 多款式模板（当前只有 T 恤）
- 自定义缝合标注 UI（当前 seams 在 JSON 里硬编码）
- GLB 导出（评审稿明确暂不作为前置）

### 关键设计

- **GarmentPattern 数据模型**：统一输入格式，几何变形路线和 Obi Cloth 路线读同一份 JSON（阶段 0 产出）
- **对照实验**：同一件 T 恤，分别跑两条路线，比较视觉可信度 × 开发时间 × iPhone 12 耗时 × 失败率
- **缝合关系**：稳定边 ID + 配对关系，不靠裁片名称猜测

### 详细方案

见 [3D成衣仿真_落地方案.md](./3D成衣仿真_落地方案.md)

### 开发环境

- Xcode 27 / iOS 17.0+ / 仅 iPhone 竖屏 / Bundle ID：`com.trailorass.app`
- 模拟器运行 CloudKit 功能需先在模拟器"设置"中登录 iCloud
- M6 POC 起需 Unity 6（免费 Personal 版）；Obi Cloth **暂缓购买**，POC 后再定
