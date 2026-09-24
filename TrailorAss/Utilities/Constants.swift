//
//  Constants.swift
//  裁缝助手 —— 全局常量
//

import Foundation

enum AppConstants {
    /// App 显示名称
    static let appName = "裁缝助手"
    /// Bundle Identifier（CloudKit 默认容器 iCloud.<bundleID> 依赖它）
    static let bundleID = "com.trailorass.app"
    static let cloudKitContainerID = "iCloud.\(bundleID)"

    /// 每页拉取条数
    static let pageSize = 20
    /// 封面图最大宽度（px）
    static let coverMaxWidth: CGFloat = 750
    /// PDF 最大大小（MB）
    static let pdfMaxSizeMB = 20
    /// 单张照片最大大小（MB）
    static let photoMaxSizeMB = 5
}
