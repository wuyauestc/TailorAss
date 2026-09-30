# TailorAss（裁缝助手）

iOS 裁缝工具 App，SwiftUI + CloudKit。需求与验收标准见 [裁缝助手PRD_v1.0_iOS版.md](裁缝助手PRD_v1.0_iOS版.md)，M1 交接细节见 [M1_交付总结.md](M1_交付总结.md)。

## 里程碑进度

| 里程碑 | 内容 | 状态 | 完成日期 |
| --- | --- | --- | --- |
| M1 | 工具集：首页九宫格、布料计算器、4 个换算器、2 张静态表 | ✅ 已完成 | 2026-09-25 |
| M2 | 图纸库：公共库图纸浏览/搜索/上传、收藏（私有库+计数双写）、我的收藏 | ✅ 已完成 | 2026-09-30 |
| M3 | 项目记录（私有库 Project） | ⏳ 未开始 | — |
| M4 | 我的页面完善 | ⏳ 未开始 | — |

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

## 开发环境

- Xcode 27 / iOS 17.0+ / 仅 iPhone 竖屏 / Bundle ID：`com.trailorass.app`
- 模拟器运行 CloudKit 功能需先在模拟器"设置"中登录 iCloud
