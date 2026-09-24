import Foundation
import CloudKit

/// CloudKit 核心服务：容器管理、账号状态、公共/私有数据库
final class CloudKitService: ObservableObject {
    static let shared = CloudKitService()

    let container: CKContainer
    let publicDB: CKDatabase
    let privateDB: CKDatabase

    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var userRecordID: CKRecord.ID?
    @Published var errorMessage: String?

    private init() {
        // 默认容器（与 Bundle ID 关联）
        self.container = CKContainer.default()
        self.publicDB = container.publicCloudDatabase
        self.privateDB = container.privateCloudDatabase

        checkAccountStatus()
        observeAccountChanges()
    }

    // MARK: - 账号状态
    func checkAccountStatus() {
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                self?.accountStatus = status
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func observeAccountChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accountDidChange),
            name: .CKAccountChanged,
            object: nil
        )
    }

    @objc private func accountDidChange() {
        checkAccountStatus()
    }

    /// 获取用户 recordID（身份识别，不做注册登录）
    func fetchUserRecordID() async throws -> CKRecord.ID {
        if let id = userRecordID { return id }
        let id = try await container.userRecordID()
        DispatchQueue.main.async { self.userRecordID = id }
        return id
    }

    // MARK: - 是否可用
    var isICloudAvailable: Bool {
        accountStatus == .available
    }

    // MARK: - 通用保存
    func save(_ record: CKRecord, in database: CKDatabase) async throws -> CKRecord {
        try await database.save(record)
    }

    func delete(_ recordID: CKRecord.ID, in database: CKDatabase) async throws {
        _ = try await database.deleteRecord(withID: recordID)
    }

    func fetch(withRecordID recordID: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord {
        try await database.record(for: recordID)
    }
}
