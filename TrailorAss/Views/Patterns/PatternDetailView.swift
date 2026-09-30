//
//  PatternDetailView.swift
//  裁缝助手 —— 5.8 图纸详情：封面大图/PDF 预览/标题作者分类/收藏按钮（双写）
//

import SwiftUI
import QuickLook

struct PatternDetailView: View {
    @StateObject private var vm: PatternDetailViewModel
    @State private var previewURL: URL?

    init(pattern: PatternItem) {
        _vm = StateObject(wrappedValue: PatternDetailViewModel(pattern: pattern))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 封面大图（3:4，宽度撑满）
                LocalFileImage(url: vm.pattern.coverFileURL)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.cornerRadius))
                    .padding(.horizontal)

                // 标题 / 作者 / 分类
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.pattern.title)
                        .font(.appTitle)
                        .foregroundColor(.appText)
                    HStack(spacing: 12) {
                        Label(vm.pattern.creatorName, systemImage: "person")
                        Label(vm.pattern.category.rawValue, systemImage: "tag")
                    }
                    .font(.appBody)
                    .foregroundColor(.appSubText)
                }
                .padding(.horizontal)

                // PDF 预览入口
                CardContainer {
                    Button {
                        previewURL = Self.preparePDFPreview(vm.pattern.pdfFileURL)
                    } label: {
                        HStack {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 22))
                                .foregroundColor(.appAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PDF 图纸")
                                    .font(.appHeadline)
                                    .foregroundColor(.appText)
                                Text("点击全屏预览（≤20MB）")
                                    .font(.appCaption)
                                    .foregroundColor(.appSubText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.appSubText)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                // 收藏按钮
                Button {
                    vm.toggleFavorite()
                } label: {
                    HStack {
                        if vm.changing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: vm.isFavorited ? "heart.fill" : "heart")
                        }
                        Text(vm.isFavorited ? "已收藏（\(vm.pattern.favoritesCount)）" : "收藏（\(vm.pattern.favoritesCount)）")
                            .font(.appHeadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.isFavorited ? Color.appSubText : Color.appAccent)
                .padding(.horizontal)
                .disabled(vm.changing)
            }
            .padding(.vertical)
        }
        .background(Color.appBackground)
        .navigationTitle("图纸详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                navHeart
            }
        }
        .quickLookPreview($previewURL)
        .iCloudGuideAlert(isPresented: $vm.showICloudGuide)
        .alert("操作失败", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .task { vm.load() }
    }

    private var navHeart: some View {
        FavoriteHeartButton(isFavorited: vm.isFavorited) { vm.toggleFavorite() }
            .disabled(vm.changing)
    }

    /// CloudKit 资产的本地缓存文件名是 UUID、没有 .pdf 后缀，
    /// QuickLook 识别不出类型，复制一份带后缀的临时文件再预览
    private static func preparePDFPreview(_ url: URL?) -> URL? {
        guard let url else { return nil }
        guard url.pathExtension.lowercased() != "pdf" else { return url }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("pattern-\(UUID().uuidString).pdf")
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return url
        }
    }
}
