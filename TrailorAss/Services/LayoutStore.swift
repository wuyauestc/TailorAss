//
//  LayoutStore.swift
//  裁缝助手 —— M5b 排料方案数据访问抽象（私有库 CRUD）
//
//  CloudKit 私有库 Record Type：Layout
//  字段：title/String、projectRecordName/String(可空，禁用 CKReference)、document/String(JSON)、cover/Asset、updatedAt/Date
//  索引：recordName=Queryable + updatedAt=Sortable
//

import Foundation
import UIKit

protocol LayoutStore {
    // MARK: iCloud 状态
    func accountState() async throws -> AccountState

    // MARK: 私有库 - 排料方案 CRUD
    /// 拉取全部方案（按 updatedAt 倒序）
    func fetchLayouts() async throws -> [LayoutItem]

    /// 拉取某项目关联的方案（按 updatedAt 倒序）
    func fetchLayouts(forProject projectRecordName: String) async throws -> [LayoutItem]

    /// 创建方案
    /// - Parameters:
    ///   - title: 方案标题
    ///   - projectRecordName: 关联项目记录名（可空）
    ///   - document: 排料文档
    ///   - coverImage: 缩略图（≤750px JPEG，自动压缩；nil 表示不保存缩略图）
    func createLayout(title: String,
                      projectRecordName: String?,
                      document: LayoutDocument,
                      coverImage: UIImage?) async throws -> LayoutItem

    /// 更新方案（document 与 coverImage 均可单独更新：coverImage 为 nil 表示不动 cover，document nil 表示不动文档）
    func updateLayout(_ layout: LayoutItem,
                      document: LayoutDocument?,
                      coverImage: UIImage?) async throws -> LayoutItem

    /// 删除方案
    func deleteLayout(recordName: String) async throws
}

/// 数据层切换入口（沿用 ProjectStore 的 Factory 模式）
enum LayoutStoreFactory {
    /// Simulator 使用本地数据，真机使用 CloudKit 私有库。
#if targetEnvironment(simulator)
    static let layoutStore: any LayoutStore = MockLayoutStore()
#else
    static let layoutStore: any LayoutStore = CloudKitLayoutStore()
#endif
}
