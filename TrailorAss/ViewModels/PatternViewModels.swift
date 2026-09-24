import Foundation
import CloudKit
import UIKit

// MARK: - 图纸库列表
final class PatternsViewModel: ObservableObject {
    @Published var patterns: [Pattern] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedCategory: String = AppConstants.PatternCategory.all.rawValue
    @Published var searchKeyword: String = ""

    private let service = PatternService()
    private var cursor: CKQueryOperation.Cursor?

    func load(reset: Bool = true) async {
        if reset { cursor = nil; patterns = [] }
        isLoading = true
        errorMessage = nil
        do {
            let (list, nextCursor) = try await service.fetchPatterns(
                category: selectedCategory == AppConstants.PatternCategory.all.rawValue ? nil : selectedCategory,
                searchKeyword: searchKeyword.isEmpty ? nil : searchKeyword,
                cursor: cursor
            )
            await MainActor.run {
                if reset { patterns = list } else { patterns.append(contentsOf: list) }
                cursor = nextCursor
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isLoading = false }
    }
}

// MARK: - 图纸详情
final class PatternDetailViewModel: ObservableObject {
    @Published var isFavorited = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    let pattern: Pattern
    private let favoriteService = FavoriteService()
    private let patternService = PatternService()

    init(pattern: Pattern) {
        self.pattern = pattern
    }

    func checkFavorite() async {
        do {
            let fav = try await favoriteService.isFavorited(patternRecordName: pattern.recordName)
            await MainActor.run { self.isFavorited = fav }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    func toggleFavorite() async {
        isLoading = true
        do {
            if isFavorited {
                try await favoriteService.removeFavorite(patternRecordName: pattern.recordName)
                try await patternService.updateFavoritesCount(recordName: pattern.recordName, delta: -1)
            } else {
                try await favoriteService.addFavorite(patternRecordName: pattern.recordName)
                try await patternService.updateFavoritesCount(recordName: pattern.recordName, delta: 1)
            }
            await MainActor.run { isFavorited.toggle() }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isLoading = false }
    }
}

// MARK: - 上传图纸
final class PatternUploadViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var category: String = AppConstants.PatternCategory.top.rawValue
    @Published var coverImage: UIImage?
    @Published var pdfData: Data?
    @Published var isUploading = false
    @Published var errorMessage: String?
    @Published var uploadSuccess = false

    private let service = PatternService()
    private let favoriteService = FavoriteService()

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && coverImage != nil && pdfData != nil
    }

    var categories: [String] {
        AppConstants.PatternCategory.allCases
            .filter { $0 != .all }
            .map { $0.rawValue }
    }

    func submit() async {
        guard canSubmit, let image = coverImage, let pdf = pdfData else { return }
        // PDF ≤20MB 校验
        guard Double(pdf.count) / 1024.0 / 1024.0 <= Double(AppConstants.pdfMaxSizeMB) else {
            errorMessage = "PDF 不能超过 \(AppConstants.pdfMaxSizeMB)MB"
            return
        }
        isUploading = true
        errorMessage = nil
        do {
            let pattern = try await service.uploadPattern(title: title, category: category, coverImage: image, pdfData: pdf)
            // 上传者默认收藏自己的图纸
            try await favoriteService.addFavorite(patternRecordName: pattern.recordName)
            await MainActor.run { uploadSuccess = true }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isUploading = false }
    }
}
