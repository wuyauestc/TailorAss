import SwiftUI

// MARK: - 我的页：我的收藏、iCloud 状态提示、关于
struct MineTabView: View {
    @EnvironmentObject private var cloudKitService: CloudKitService
    @State private var favorites: [Favorite] = []
    @State private var favoritedPatterns: [Pattern] = []
    @State private var isLoading = false

    private let favoriteService = FavoriteService()
    private let patternService = PatternService()

    var body: some View {
        NavigationStack {
            List {
                // iCloud 状态
                Section {
                    HStack {
                        Image(systemName: cloudKitService.isICloudAvailable ? "icloud.fill" : "icloud.slash")
                            .foregroundColor(cloudKitService.isICloudAvailable ? .appAccent : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cloudKitService.isICloudAvailable ? "iCloud 已登录" : "iCloud 未登录")
                                .font(.appBody)
                                .foregroundColor(.appText)
                            if !cloudKitService.isICloudAvailable {
                                Text("收藏、上传、项目功能需要 iCloud")
                                    .font(.appCaption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }

                // 我的收藏
                Section("我的收藏（\(favoritedPatterns.count)）") {
                    if isLoading {
                        ProgressView()
                    } else if favoritedPatterns.isEmpty {
                        Text("暂无收藏").foregroundColor(.appSubText)
                    } else {
                        ForEach(favoritedPatterns) { pattern in
                            NavigationLink {
                                PatternDetailView(pattern: pattern)
                            } label: {
                                HStack(spacing: 12) {
                                    if let url = pattern.coverURL,
                                       let data = try? Data(contentsOf: url),
                                       let img = UIImage(data: data) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 48, height: 48)
                                            .clipped()
                                            .cornerRadius(6)
                                    }
                                    VStack(alignment: .leading) {
                                        Text(pattern.title).font(.appBody).foregroundColor(.appText)
                                        Text(pattern.category).font(.appCaption).foregroundColor(.appSubText)
                                    }
                                }
                            }
                        }
                    }
                }

                // 关于
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0").foregroundColor(.appSubText)
                    }
                    HStack {
                        Text("应用名称")
                        Spacer()
                        Text(AppConstants.appName).foregroundColor(.appSubText)
                    }
                    Text("数据通过 iCloud 同步，公共图纸库共享，个人项目与收藏按账号隔离")
                        .font(.appCaption)
                        .foregroundColor(.appSubText)
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .task { await loadFavorites() }
            .refreshable { await loadFavorites() }
        }
    }

    private func loadFavorites() async {
        guard cloudKitService.isICloudAvailable else { return }
        isLoading = true
        do {
            let favs = try await favoriteService.fetchFavorites()
            favorites = favs
            let patternNames = favs.map { $0.patternRecordName }
            let patterns = try await patternService.fetchPatterns(recordNames: patternNames)
            await MainActor.run { favoritedPatterns = patterns }
        } catch {
            // 静默
        }
        await MainActor.run { isLoading = false }
    }
}
