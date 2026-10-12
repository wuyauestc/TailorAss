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
| M5b | 排料增强：一键全角度自动排列、排料存入项目（CloudKit） | ⏳ 未开始 | — |

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

## 开发环境

- Xcode 27 / iOS 17.0+ / 仅 iPhone 竖屏 / Bundle ID：`com.trailorass.app`
- 模拟器运行 CloudKit 功能需先在模拟器"设置"中登录 iCloud
