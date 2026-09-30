//
//  PlaceholderTabViews.swift
//  裁缝助手 —— 项目 Tab（M3 实现）/ 我的 Tab（收藏入口 M2 已接通）
//

import SwiftUI

// MARK: - Tab 3 项目（M3）
struct ProjectsTabView: View {
    var body: some View {
        NavigationStack {
            ComingSoonView(
                title: "我的缝纫项目",
                message: "项目创建、状态流转、材料清单与成品照片将在 M3 里程碑上线（需要 iCloud / CloudKit）。"
            )
            .navigationTitle("项目")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Tab 4 我的
struct MineTabView: View {
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iCloud 状态")
                            .font(.appBody)
                            .foregroundColor(.appText)
                        Text("图纸收藏、上传与项目同步需登录 iCloud 并开启 CloudKit。M2 开发期间使用本地模拟数据，无需登录也可体验。")
                            .font(.appCaption)
                            .foregroundColor(.appSubText)
                    }
                }
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.appSubText)
                    }
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 通用"敬请期待"占位
struct ComingSoonView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 44))
                .foregroundColor(.appAccent)
            Text(title)
                .font(.appTitle)
                .foregroundColor(.appText)
            Text(message)
                .font(.appBody)
                .foregroundColor(.appSubText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}
