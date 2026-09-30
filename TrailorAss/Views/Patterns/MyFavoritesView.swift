//
//  MyFavoritesView.swift
//  裁缝助手 —— 我的收藏（私有库 Favorite 关联公共库 Pattern）
//

import SwiftUI

struct MyFavoritesView: View {
    @StateObject private var vm = MyFavoritesViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView("加载中…")
            } else if vm.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.appSubText)
                    Text("还没有收藏图纸")
                        .font(.appBody)
                        .foregroundColor(.appSubText)
                    Text("在「图纸」里看到喜欢的，点 ♥ 收藏")
                        .font(.appCaption)
                        .foregroundColor(.appSubText)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(vm.items) { item in
                            NavigationLink(value: item) {
                                PatternCardView(item: item, isFavorited: true) {
                                    vm.removeFavorite(item)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color.appBackground)
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PatternItem.self) { PatternDetailView(pattern: $0) }
        .iCloudGuideAlert(isPresented: $vm.showICloudGuide)
        .task { vm.load() }
    }
}
