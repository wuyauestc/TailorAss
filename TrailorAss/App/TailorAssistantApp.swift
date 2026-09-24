import SwiftUI
import CloudKit

@main
struct TailorAssistantApp: App {
    @StateObject private var cloudKitService = CloudKitService.shared
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(cloudKitService)
                .environmentObject(appState)
                .preferredColorScheme(.light) // 1.0 强制浅色
        }
    }
}

/// 全局应用状态
final class AppState: ObservableObject {
    /// 当前 iCloud 账号状态
    @Published var iCloudStatus: CKAccountStatus = .couldNotDetermine

    /// iCloud 用户 recordID（用于身份识别，不做注册登录）
    @Published var userRecordID: CKRecord.ID?
}
