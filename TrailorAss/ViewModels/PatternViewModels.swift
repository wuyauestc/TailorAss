//
//  PatternViewModels.swift
//  裁缝助手 —— M2 图纸库视图模型（列表 / 详情 / 上传 / 我的收藏）
//

import SwiftUI
import UIKit
import Combine
import CloudKit
import PhotosUI

// MARK: - 列表
@MainActor
final class PatternsListViewModel: ObservableObject {
    @Published var items: [PatternItem] = []
    @Published var selectedCategory: PatternCategory?   // nil = 全部
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = true
    @Published var errorMessage: String?
    @Published var favoriteNames: Set<String> = []
    @Published var showUpload = false
    /// 未登录 iCloud 时点上传：弹引导
    @Published var showICloudGuide = false

    private let store: any PatternStore = StoreFactory.patternStore
    private var page = 0
    private var reloadTask: Task<Void, Never>?

    func onAppear() {
        guard items.isEmpty else { return }
        reload()
    }

    func reload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            // 输入停顿 300ms 再发查询，避免逐字搜索
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await self.fetch(reset: true)
        }
    }

    func loadMoreIfNeeded(_ item: PatternItem) {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        // 距最后 5 条开始预加载
        guard let idx = items.firstIndex(where: { $0.recordName == item.recordName }),
              idx >= items.count - 5 else { return }
        Task { await fetch(reset: false) }
    }

    func changeCategory(_ category: PatternCategory?) {
        selectedCategory = category
        reload()
    }

    /// 上传完成后回到第一页刷新
    func handleUploaded() {
        reload()
    }

    func checkUploadAvailability() {
        Task {
            let state = (try? await store.accountState()) ?? .unavailable
            if state == .available {
                showUpload = true
            } else {
                showICloudGuide = true
            }
        }
    }

    func refreshFavoriteNames() {
        Task {
            if let names = try? await store.favoriteRecordNames() {
                self.favoriteNames = names
            }
        }
    }

    func isFavorited(_ item: PatternItem) -> Bool {
        favoriteNames.contains(item.recordName)
    }

    /// 列表卡片上直接点爱心：收藏/取消并即时反映计数
    func toggleFavoriteFromList(_ item: PatternItem) {
        let target = !favoriteNames.contains(item.recordName)
        Task {
            do {
                let state = try await store.accountState()
                guard state == .available else {
                    showICloudGuide = true
                    return
                }
                let updated = try await store.setFavorite(pattern: item, isFavorite: target)
                applyUpdate(updated)
                if target { favoriteNames.insert(item.recordName) } else {
                    favoriteNames.remove(item.recordName)
                }
            } catch StoreError.requiresICloud {
                showICloudGuide = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func applyUpdate(_ updated: PatternItem) {
        if let idx = items.firstIndex(where: { $0.recordName == updated.recordName }) {
            items[idx] = updated
        }
    }

    private func fetch(reset: Bool) async {
        if reset {
            page = 0
            hasMore = true
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            let batch = try await store.fetchPatterns(
                category: selectedCategory,
                searchText: searchText,
                page: page
            )
            if Task.isCancelled { return }
            if reset { items = batch } else { items.append(contentsOf: batch) }
            hasMore = batch.count >= AppConstants.pageSize
            if !batch.isEmpty { page += 1 }
            refreshFavoriteNames()
        } catch is CancellationError {
            // 取消不提示
        } catch let e as CKError where e.code == .operationCancelled {
            // 连续输入时上一个查询被 CloudKit 取消，不提示
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 详情
@MainActor
final class PatternDetailViewModel: ObservableObject {
    @Published var pattern: PatternItem
    @Published var isFavorited = false
    @Published var changing = false
    @Published var showICloudGuide = false
    @Published var errorMessage: String?

    private let store: any PatternStore = StoreFactory.patternStore

    init(pattern: PatternItem) {
        self.pattern = pattern
    }

    func load() {
        Task {
            if let names = try? await store.favoriteRecordNames() {
                isFavorited = names.contains(pattern.recordName)
            }
        }
    }

    func toggleFavorite() {
        guard !changing else { return }
        let target = !isFavorited
        changing = true
        Task {
            defer { changing = false }
            do {
                let state = try await store.accountState()
                guard state == .available else {
                    showICloudGuide = true
                    return
                }
                let updated = try await store.setFavorite(pattern: pattern, isFavorite: target)
                pattern = updated
                isFavorited = target
            } catch StoreError.requiresICloud {
                showICloudGuide = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - 我的收藏
@MainActor
final class MyFavoritesViewModel: ObservableObject {
    @Published var items: [PatternItem] = []
    @Published var isLoading = false
    @Published var showICloudGuide = false
    @Published var errorMessage: String?

    private let store: any PatternStore = StoreFactory.patternStore

    func load() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let state = try await store.accountState()
                guard state == .available else {
                    showICloudGuide = true
                    items = []
                    return
                }
                items = try await store.fetchFavoritePatterns()
            } catch StoreError.requiresICloud {
                showICloudGuide = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 在收藏列表里点爱心：取消收藏并从列表移除
    func removeFavorite(_ item: PatternItem) {
        Task {
            do {
                _ = try await store.setFavorite(pattern: item, isFavorite: false)
                items.removeAll { $0.recordName == item.recordName }
            } catch StoreError.requiresICloud {
                showICloudGuide = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - 上传
@MainActor
final class PatternUploadViewModel: ObservableObject {
    @Published var title = ""
    @Published var category: PatternCategory = .top
    @Published var photoItem: PhotosPickerItem? {
        didSet { loadCover() }
    }
    @Published var coverImage: UIImage?
    @Published var pdfURL: URL?
    @Published var pdfName: String?
    @Published var pdfError: String?
    @Published var submitting = false
    @Published var errorMessage: String?
    @Published var showICloudGuide = false
    @Published var didSucceed = false

    private let store: any PatternStore = StoreFactory.patternStore
    private var coverJPEGURL: URL?

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
        && coverJPEGURL != nil
        && pdfURL != nil
        && pdfError == nil
        && !submitting
    }

    /// 封面图加载并压缩到宽 ≤750px JPEG，写临时文件
    private func loadCover() {
        coverImage = nil
        coverJPEGURL = nil
        guard let photoItem else { return }
        Task {
            guard let data = try? await photoItem.loadTransferable(type: Data.self),
                  let (image, jpeg) = MediaUtils.compressCover(data: data),
                  let url = try? MediaUtils.writeToTempFile(data: jpeg, ext: "jpg") else {
                errorMessage = "封面图读取失败，请换一张"
                return
            }
            coverImage = image
            coverJPEGURL = url
        }
    }

    /// PDF 选择结果（fileImporter 回调中已 start/stop accessing）
    func handlePickedPDF(_ url: URL) {
        pdfError = nil
        pdfURL = nil
        pdfName = nil
        guard MediaUtils.isPDFSizeValid(url) else {
            pdfError = StoreError.invalidPDFSize.errorDescription
            return
        }
        // 复制进临时目录持有（fileImporter 的安全域 URL 在闭包外不可用）
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            pdfURL = dest
            pdfName = url.lastPathComponent
        } catch {
            pdfError = "PDF 读取失败：\(error.localizedDescription)"
        }
    }

    func submit() {
        guard let coverJPEGURL, let pdfURL else { return }
        submitting = true
        errorMessage = nil
        Task {
            defer { submitting = false }
            do {
                let state = try await store.accountState()
                guard state == .available else {
                    showICloudGuide = true
                    return
                }
                _ = try await store.uploadPattern(
                    title: title,
                    category: category,
                    coverJPEGURL: coverJPEGURL,
                    pdfFileURL: pdfURL
                )
                didSucceed = true
            } catch StoreError.requiresICloud {
                showICloudGuide = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
