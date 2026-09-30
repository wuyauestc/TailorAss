//
//  PatternStore.swift
//  裁缝助手 —— M2 数据访问抽象（Mock / CloudKit 双实现，业务层只依赖本协议）
//
//  账号审核通过、Xcode 配好 iCloud + CloudKit 后：
//  将 StoreFactory.patternStore 从 MockPatternStore() 改为 CloudKitPatternStore()
//

import Foundation

protocol PatternStore {

    // MARK: iCloud 状态
    /// 当前 iCloud 账号状态。浏览公共库不要求 available；收藏/上传要求 available
    func accountState() async throws -> AccountState

    // MARK: 公共库 - 图纸
    /// 分页拉取图纸（按上传时间倒序，每页 20 条）
    /// - Parameters:
    ///   - category: nil 表示"全部"
    ///   - searchText: nil/空表示不按标题过滤
    ///   - page: 从 0 开始
    func fetchPatterns(category: PatternCategory?,
                       searchText: String?,
                       page: Int) async throws -> [PatternItem]

    // MARK: 私有库 - 收藏
    /// 批量查询某图纸是否已被当前用户收藏（用于列表/详情显示心形状态）
    func favoriteRecordNames() async throws -> Set<String>

    /// 收藏/取消收藏。
    /// 收藏：私有库写 Favorite + 公共库 favoritesCount +1；
    /// 取消：删 Favorite + favoritesCount -1。
    /// 返回更新收藏数后的图纸。
    func setFavorite(pattern: PatternItem, isFavorite: Bool) async throws -> PatternItem

    /// 我收藏的图纸（私有库 Favorite 关联公共库 Pattern 得到完整信息）
    func fetchFavoritePatterns() async throws -> [PatternItem]

    // MARK: 上传
    /// 上传图纸到公共库。封面为已压缩 JPEG 的文件 URL，PDF 已校验 ≤20MB。
    /// 上传成功后：上传者自动收藏自己的图纸（favoritesCount = 1）。
    func uploadPattern(title: String,
                       category: PatternCategory,
                       coverJPEGURL: URL,
                       pdfFileURL: URL) async throws -> PatternItem
}

/// 数据层切换入口
enum StoreFactory {
    /// M2 已接入 CloudKit（Development 环境）。
    /// 若需回到本地假数据调试 UI，改为 MockPatternStore() 即可
    static let patternStore: any PatternStore = CloudKitPatternStore()
}
