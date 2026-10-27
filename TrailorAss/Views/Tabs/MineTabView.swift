//
//  MineTabView.swift
//  裁缝助手 —— M4 我的页面（我的收藏 / iCloud 实时状态 / 关于）
//

import SwiftUI
import Combine

// MARK: - iCloud 账号状态检测
@MainActor
final class ICloudStatusModel: ObservableObject {
    @Published var state: AccountState = .unavailable
    @Published var isChecking = false

    func refresh() async {
        isChecking = true
        do {
            state = try await ProjectStoreFactory.projectStore.accountState()
        } catch {
            state = .unavailable
        }
        isChecking = false
    }
}

// MARK: - 我的 Tab
struct MineTabView: View {
    @StateObject private var iCloud = ICloudStatusModel()

    private var versionString: String {
        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(ver) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("我的内容") {
                    NavigationLink {
                        MyFavoritesView()
                    } label: {
                        Label("我的收藏", systemImage: "heart.fill")
                            .foregroundColor(.appText)
                    }
                }

                Section("iCloud") {
                    HStack {
                        if iCloud.isChecking {
                            ProgressView()
                        } else {
                            Image(systemName: iCloud.state == .available
                                  ? "checkmark.icloud.fill"
                                  : "exclamationmark.icloud")
                                .foregroundColor(iCloud.state == .available ? .green : .orange)
                        }
                        Text("账号状态")
                            .foregroundColor(.appText)
                        Spacer()
                        Text(iCloud.state == .available ? "已登录" : "未登录")
                            .font(.appCaption)
                            .foregroundColor(.appSubText)
                        Button("刷新") {
                            Task { await iCloud.refresh() }
                        }
                        .font(.appCaption)
                        .buttonStyle(.borderless)
                    }
                    if iCloud.state != .available {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("去系统设置登录 iCloud", systemImage: "arrow.up.right.icloud")
                                .foregroundColor(.appAccent)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("图纸收藏、上传与项目数据通过 iCloud（CloudKit）自动同步，仅你本人可见私有数据。")
                            .font(.appCaption)
                            .foregroundColor(.appSubText)
                    }
                }

                Section("关于") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于裁缝助手", systemImage: "info.circle")
                            .foregroundColor(.appText)
                    }
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(versionString)
                            .font(.appCaption)
                            .foregroundColor(.appSubText)
                    }
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .task { await iCloud.refresh() }
            .refreshable { await iCloud.refresh() }
        }
    }
}

// MARK: - 关于页
struct AboutView: View {
    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "scissors")
                    .font(.system(size: 52))
                    .foregroundColor(.appAccent)
                    .padding(.top, 32)
                Text("裁缝助手")
                    .font(.appTitle)
                    .foregroundColor(.appText)
                Text("版本 \(versionString)")
                    .font(.appCaption)
                    .foregroundColor(.appSubText)

                CardContainer {
                    Text("为裁缝打造的随身工具箱：布料用量计算、常用单位换算、图纸共享浏览，以及缝纫项目的材料与进度管理。\n\n工具数据保存在本机；图纸与项目通过你的 iCloud 同步，换设备不丢失。")
                        .font(.appBody)
                        .foregroundColor(.appText)
                        .lineSpacing(4)
                }
                .padding(.horizontal)

                NavigationLink {
                    ThirdPartyLicensesView()
                } label: {
                    Label("第三方软件许可", systemImage: "doc.text")
                        .font(.appBody)
                        .foregroundColor(.appAccent)
                }
                .padding(.horizontal)

                Spacer(minLength: 24)
                Text("© 2026 TailorAss")
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThirdPartyLicensesView: View {
    private let content: String = {
        guard let url = Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "许可文件未包含在当前构建中。"
        }
        return text
    }()

    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("第三方软件许可")
        .navigationBarTitleDisplayMode(.inline)
    }
}
