//
//  PatternsTabView.swift
//  裁缝助手 —— 5.8 图纸列表页：分类筛选 + 标题搜索 + 网格卡片 + 分页 + 上传入口
//

import SwiftUI

struct PatternsTabView: View {
    @StateObject private var vm = PatternsListViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryBar
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(vm.items) { item in
                            NavigationLink(value: item) {
                                PatternCardView(
                                    item: item,
                                    isFavorited: vm.isFavorited(item),
                                    onTapHeart: { vm.toggleFavoriteFromList(item) }
                                )
                            }
                            .buttonStyle(.plain)
                            .onAppear { vm.loadMoreIfNeeded(item) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                    footer
                }
                .refreshable { vm.reload() }
                .searchable(text: $vm.searchText, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "搜索图纸标题")
                .onChange(of: vm.searchText) { _, _ in
                    // 延迟到下一 runloop，避免在视图更新周期内同步改 @Published
                    Task { @MainActor in vm.reload() }
                }
            }
            .background(Color.appBackground)
            .navigationTitle("图纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.checkUploadAvailability()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                    }
                }
            }
            .navigationDestination(for: PatternItem.self) { item in
                PatternDetailView(pattern: item)
            }
            .sheet(isPresented: $vm.showUpload, onDismiss: { vm.handleUploaded() }) {
                PatternUploadView()
            }
            .iCloudGuideAlert(isPresented: $vm.showICloudGuide)
            .alert("加载失败", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("重试") { vm.reload() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .task { vm.onAppear() }
        }
    }

    // MARK: 顶部分类 chips（全部/上衣/裙装/裤装/童装/包袋/家居）
    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PatternCategory.filterOptions, id: \.self) { option in
                    let isSelected = vm.selectedCategory == option
                    Button {
                        vm.changeCategory(option)
                    } label: {
                        Text(option?.rawValue ?? "全部")
                            .font(.appBody)
                            .foregroundColor(isSelected ? .white : .appText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.appAccent : Color.appCard)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.appDivider, lineWidth: isSelected ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.appBackground)
    }

    @ViewBuilder
    private var footer: some View {
        if vm.isLoading || vm.isLoadingMore {
            ProgressView()
                .padding(.vertical, 16)
        } else if vm.items.isEmpty && vm.errorMessage == nil {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40))
                    .foregroundColor(.appSubText)
                Text(vm.searchText.isEmpty ? "还没有图纸，点右上角 ＋ 上传第一张吧" : "没有找到相关图纸")
                    .font(.appBody)
                    .foregroundColor(.appSubText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        } else if !vm.hasMore && !vm.items.isEmpty {
            Text("— 没有更多了 —")
                .font(.appCaption)
                .foregroundColor(.appSubText)
                .padding(.vertical, 16)
        }
    }
}

// MARK: - 网格卡片：封面 + 标题 + 收藏数
struct PatternCardView: View {
    let item: PatternItem
    let isFavorited: Bool
    let onTapHeart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LocalFileImage(url: item.coverFileURL)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 3) {
                        FavoriteHeartButton(isFavorited: isFavorited, action: onTapHeart)
                        Text("\(item.favoritesCount)")
                            .font(.appCaption)
                            .foregroundColor(.appSubText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(6)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.appBody)
                    .foregroundColor(.appText)
                    .lineLimit(1)
                Text(item.category.rawValue)
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.appCard)
        .cornerRadius(AppStyle.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: AppStyle.cardShadowRadius,
                x: 0, y: AppStyle.cardShadowY)
    }
}
