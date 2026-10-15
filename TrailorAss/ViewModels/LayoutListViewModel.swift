//
//  LayoutListViewModel.swift
//  裁缝助手 —— M5b 排料方案列表 VM
//

import SwiftUI
import Combine
import CloudKit

@MainActor
final class LayoutListViewModel: ObservableObject {
    @Published var layouts: [LayoutItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store = LayoutStoreFactory.layoutStore

    /// nil = 全部方案；非空 = 仅该项目关联方案
    func load(projectRecordName: String? = nil) async {
        isLoading = true
        errorMessage = nil
        do {
            if let projectRecordName {
                layouts = try await store.fetchLayouts(forProject: projectRecordName)
            } else {
                layouts = try await store.fetchLayouts()
            }
        } catch is CancellationError {
        } catch let e as CKError where e.code == .operationCancelled {
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
        isLoading = false
    }

    func delete(_ layout: LayoutItem) async {
        do {
            try await store.deleteLayout(recordName: layout.recordName)
            layouts.removeAll { $0.recordName == layout.recordName }
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}
