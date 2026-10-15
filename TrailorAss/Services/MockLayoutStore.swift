//
//  MockLayoutStore.swift
//  裁缝助手 —— M5b 排料方案本地假数据（离线调试 UI，无需 iCloud）
//

import Foundation
import UIKit

final class MockLayoutStore: LayoutStore {
    func accountState() async throws -> AccountState { .available }

    func fetchLayouts() async throws -> [LayoutItem] { [] }

    func fetchLayouts(forProject projectRecordName: String) async throws -> [LayoutItem] { [] }

    func createLayout(title: String,
                      projectRecordName: String?,
                      document: LayoutDocument,
                      coverImage: UIImage?) async throws -> LayoutItem {
        let json = CloudKitLayoutStore.encodeDocument(document)
        return LayoutItem(recordName: "mock-\(UUID().uuidString.prefix(8))",
                          title: title,
                          projectRecordName: projectRecordName,
                          documentJSON: json,
                          coverURL: nil,
                          updatedAt: Date())
    }

    func updateLayout(_ layout: LayoutItem,
                      document: LayoutDocument?,
                      coverImage: UIImage?) async throws -> LayoutItem {
        var updated = layout
        if let document {
            updated.documentJSON = CloudKitLayoutStore.encodeDocument(document)
        }
        updated.updatedAt = Date()
        return updated
    }

    func deleteLayout(recordName: String) async throws {}
}
