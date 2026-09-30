//
//  MockPatternStore.swift
//  裁缝助手 —— 本地模拟数据实现（开发者账号审核期间使用，行为与 CloudKit 版本一致）
//

import UIKit

/// 图纸库模拟数据源：内存数据 + 本地生成的占位封面图/PDF，所有方法 async 模拟网络延迟
actor MockPatternStore: PatternStore {

    private var patterns: [PatternItem] = []
    /// 收藏表：recordName -> FavoriteItem（模拟私有库，按设备隔离）
    private var favorites: [String: FavoriteItem] = [:]
    /// 已知图纸索引（收藏列表需要拿到完整 Pattern 信息）
    private var knownIndex: [String: PatternItem] = [:]
    private let pageSize = AppConstants.pageSize

    init() {
        seed()
    }

    // MARK: iCloud
    func accountState() async throws -> AccountState {
        // 模拟环境恒为已登录；未登录引导弹窗的 UI 路径在 CloudKit 版本触发
        .available
    }

    // MARK: 列表
    func fetchPatterns(category: PatternCategory?,
                       searchText: String?,
                       page: Int) async throws -> [PatternItem] {
        try await Task.sleep(for: .milliseconds(350))
        let keyword = (searchText ?? "").trimmingCharacters(in: .whitespaces)
        let filtered = patterns
            .filter { category == nil || $0.category == category }
            .filter { keyword.isEmpty || $0.title.localizedCaseInsensitiveContains(keyword) }
        let start = page * pageSize
        guard start < filtered.count else { return [] }
        let end = min(start + pageSize, filtered.count)
        return Array(filtered[start..<end])
    }

    // MARK: 收藏
    func favoriteRecordNames() async throws -> Set<String> {
        Set(favorites.keys)
    }

    func setFavorite(pattern: PatternItem, isFavorite: Bool) async throws -> PatternItem {
        try await Task.sleep(for: .milliseconds(300))
        var updated = pattern
        if isFavorite {
            guard favorites[pattern.recordName] == nil else { return pattern }
            favorites[pattern.recordName] = FavoriteItem(patternRecordName: pattern.recordName,
                                                         createdAt: Date())
            updated.favoritesCount += 1
        } else {
            guard favorites.removeValue(forKey: pattern.recordName) != nil else { return pattern }
            updated.favoritesCount = max(0, updated.favoritesCount - 1)
        }
        // 同步更新本地索引与列表
        knownIndex[updated.recordName] = updated
        if let idx = patterns.firstIndex(where: { $0.recordName == updated.recordName }) {
            patterns[idx] = updated
        }
        return updated
    }

    func fetchFavoritePatterns() async throws -> [PatternItem] {
        try await Task.sleep(for: .milliseconds(300))
        return favorites.values
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { knownIndex[$0.patternRecordName] }
    }

    // MARK: 上传
    func uploadPattern(title: String,
                       category: PatternCategory,
                       coverJPEGURL: URL,
                       pdfFileURL: URL) async throws -> PatternItem {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw StoreError.emptyTitle }
        guard FileManager.default.fileExists(atPath: coverJPEGURL.path) else { throw StoreError.missingCover }
        guard FileManager.default.fileExists(atPath: pdfFileURL.path) else { throw StoreError.missingPDF }
        guard MediaUtils.isPDFSizeValid(pdfFileURL) else { throw StoreError.invalidPDFSize }
        try await Task.sleep(for: .milliseconds(800))

        // 复制进 Mock 资源目录，避免临时文件被系统回收
        let dir = try Self.resourceDirectory()
        let baseName = UUID().uuidString
        let coverDest = dir.appendingPathComponent("\(baseName)_cover.jpg")
        let pdfDest = dir.appendingPathComponent("\(baseName).pdf")
        try? FileManager.default.removeItem(at: coverDest)
        try? FileManager.default.removeItem(at: pdfDest)
        try FileManager.default.copyItem(at: coverJPEGURL, to: coverDest)
        try FileManager.default.copyItem(at: pdfFileURL, to: pdfDest)

        let recordName = "mock-\(UUID().uuidString)"
        let item = PatternItem(recordName: recordName,
                               title: trimmed,
                               category: category,
                               creatorName: "裁缝用户",
                               favoritesCount: 1,            // 上传者默认收藏
                               createdAt: Date(),
                               coverFileURL: coverDest,
                               pdfFileURL: pdfDest)
        patterns.insert(item, at: 0)
        knownIndex[recordName] = item
        favorites[recordName] = FavoriteItem(patternRecordName: recordName, createdAt: Date())
        return item
    }

    // MARK: - 种子数据（46 条，覆盖 6 个分类，超过一页 20 条以验证分页）
    private func seed() {
        let titles: [(String, PatternCategory)] = [
            ("法式碎花连衣裙", .skirt), ("基础款直筒裤", .pants), ("儿童卫衣套装", .kids),
            ("通勤托特包", .bag), ("亚麻抱枕套", .home), ("白衬衫经典款", .top),
            ("高腰A字半裙", .skirt), ("阔腿牛仔裤", .pants), ("婴儿连体衣", .kids),
            ("帆布购物袋", .bag), ("桌旗与餐垫套装", .home), ("V领针织衫", .top),
            ("百褶长裙", .skirt), ("九分西装裤", .pants), ("儿童背带裤", .kids),
            ("水桶包", .bag), ("厨房围裙", .home), ("落肩宽松T恤", .top),
            ("鱼尾裙", .skirt), ("松紧腰家居裤", .pants), ("儿童连衣裙", .kids),
            ("斜挎小方包", .bag), ("沙发靠垫三件套", .home), ("立领衬衫", .top),
            ("裹身裙", .skirt), ("锥形休闲裤", .pants), ("宝宝罩衣", .kids),
            ("化妆收纳包", .bag), ("微波炉防尘罩", .home), ("泡泡袖上衣", .top),
            ("背带裙", .skirt), ("短裤纸样", .pants), ("儿童马甲", .kids),
            ("双肩背包", .bag), ("窗帘绑带", .home), ("方领罩衫", .top),
            ("大摆伞裙", .skirt), ("直筒西裤", .pants), ("儿童校服裙", .kids),
            ("口金包", .bag), ("餐椅坐垫套", .home), ("无袖背心", .top),
            ("包臀裙", .skirt), ("灯笼裤", .pants), ("儿童披风", .kids),
            ("旅行收纳袋", .bag)
        ]
        let dir = try? Self.resourceDirectory()
        var items: [PatternItem] = []
        for (index, pair) in titles.enumerated() {
            let baseName = "seed-\(index)"
            var coverURL: URL?
            var pdfURL: URL?
            if let dir {
                let c = dir.appendingPathComponent("\(baseName)_cover.jpg")
                let p = dir.appendingPathComponent("\(baseName).pdf")
                if !FileManager.default.fileExists(atPath: c.path) {
                    Self.makePlaceholderCover(title: pair.0, category: pair.1, writeTo: c)
                }
                if !FileManager.default.fileExists(atPath: p.path) {
                    Self.makePlaceholderPDF(title: pair.0, writeTo: p)
                }
                coverURL = c
                pdfURL = p
            }
            // 时间逐条往前，保证 createdAt 倒序稳定
            let date = Date().addingTimeInterval(TimeInterval(-(titles.count - index) * 3600))
            let item = PatternItem(recordName: "mock-seed-\(index)",
                                   title: pair.0,
                                   category: pair.1,
                                   creatorName: "裁缝用户",
                                   favoritesCount: (index % 7),
                                   createdAt: date,
                                   coverFileURL: coverURL,
                                   pdfFileURL: pdfURL)
            items.append(item)
        }
        self.patterns = items
        items.forEach { knownIndex[$0.recordName] = $0 }
    }

    /// 沙盒中的 Mock 资源目录
    private static func resourceDirectory() throws -> URL {
        let dir = FileManager.default.cachesDirectory
            .appendingPathComponent("MockPatterns", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 生成带标题文字的占位封面（300×400 JPEG）
    private static func makePlaceholderCover(title: String, category: PatternCategory, writeTo url: URL) {
        let size = CGSize(width: 300, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            category.placeholderColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            (title as NSString).draw(with: CGRect(x: 16, y: 170, width: 268, height: 60),
                                     options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                .paragraphStyle: paragraph
            ]
            (category.rawValue as NSString).draw(with: CGRect(x: 16, y: 240, width: 268, height: 24),
                                                 options: .usesLineFragmentOrigin, attributes: subAttrs, context: nil)
        }
        try? image.jpegData(compressionQuality: 0.8)?.write(to: url, options: .atomic)
    }

    /// 生成一页占位 PDF
    private static func makePlaceholderPDF(title: String, writeTo url: URL) {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            context.beginPage()
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold)
            ]
            (title as NSString).draw(at: CGPoint(x: 72, y: 100), withAttributes: titleAttrs)
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.darkGray
            ]
            ("裁缝助手 · 示例图纸（Mock 数据）\n正式图纸将在 M2 接入 CloudKit 后由用户上传。" as NSString)
                .draw(with: CGRect(x: 72, y: 160, width: 468, height: 80),
                      options: .usesLineFragmentOrigin, attributes: bodyAttrs, context: nil)
        }
        try? data.write(to: url, options: .atomic)
    }
}

private extension PatternCategory {
    /// 占位封面底色
    var placeholderColor: UIColor {
        switch self {
        case .top:   return UIColor(red: 0.55, green: 0.44, blue: 0.32, alpha: 1)
        case .skirt: return UIColor(red: 0.72, green: 0.45, blue: 0.48, alpha: 1)
        case .pants: return UIColor(red: 0.40, green: 0.48, blue: 0.55, alpha: 1)
        case .kids:  return UIColor(red: 0.78, green: 0.60, blue: 0.35, alpha: 1)
        case .bag:   return UIColor(red: 0.45, green: 0.55, blue: 0.42, alpha: 1)
        case .home:  return UIColor(red: 0.58, green: 0.50, blue: 0.62, alpha: 1)
        }
    }
}

private extension FileManager {
    var cachesDirectory: URL {
        urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
}
