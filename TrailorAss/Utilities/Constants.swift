import Foundation

// MARK: - 全局常量
enum AppConstants {
    /// App 显示名称
    static let appName = "TrailorAss"
    /// Bundle Identifier
    static let bundleID = "com.trailorass.app"
    /// CloudKit 容器（默认容器，与 Bundle ID 关联）
    static let cloudKitContainerID = "iCloud.\(bundleID)"

    /// 每页拉取条数
    static let pageSize: Int = 20
    /// 封面图最大宽度（px）
    static let coverMaxWidth: CGFloat = 750
    /// PDF 最大大小（MB）
    static let pdfMaxSizeMB: Int = 20
    /// 单张照片最大大小（MB）
    static let photoMaxSizeMB: Int = 5

    /// 项目状态枚举
    enum ProjectStatus: String, CaseIterable {
        case planning = "planning"
        case cutting = "cutting"
        case sewing = "sewing"
        case finished = "finished"

        var displayName: String {
            switch self {
            case .planning: return "规划中"
            case .cutting: return "裁剪中"
            case .sewing: return "车缝中"
            case .finished: return "已完成"
            }
        }

        /// 相邻状态切换：仅可向前推进；finished 可重新打开为 sewing
        func canTransition(to next: ProjectStatus) -> Bool {
            switch (self, next) {
            case (.planning, .cutting),
                 (.cutting, .sewing),
                 (.sewing, .finished),
                 (.finished, .sewing):
                return true
            default:
                return false
            }
        }

        var next: ProjectStatus? {
            switch self {
            case .planning: return .cutting
            case .cutting: return .sewing
            case .sewing: return .finished
            case .finished: return nil
            }
        }
    }

    /// 图纸分类
    enum PatternCategory: String, CaseIterable {
        case all = "全部"
        case top = "上衣"
        case skirt = "裙装"
        case pants = "裤装"
        case kids = "童装"
        case bag = "包袋"
        case home = "家居"
    }
}
