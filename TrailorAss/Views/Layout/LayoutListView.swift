//
//  LayoutListView.swift
//  裁缝助手 —— M5b 排料方案列表（首页入口与项目详情区块共用）
//

import SwiftUI

struct LayoutListView: View {
    @StateObject private var vm = LayoutListViewModel()

    /// nil = 全部方案；非空 = 仅该项目关联方案
    private let projectRecordName: String?
    /// 显示在导航栏的标题
    private let navTitle: String

    init(projectRecordName: String? = nil, navTitle: String = "排料方案") {
        self.projectRecordName = projectRecordName
        self.navTitle = navTitle
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.layouts.isEmpty {
                ProgressView().frame(maxHeight: .infinity)
            } else if vm.layouts.isEmpty {
                emptyState
            } else {
                layoutList
            }
        }
        .appBackground()
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // 新建方案：进入空白画板
                NavigationLink {
                    LayoutBoardView(editingLayout: nil,
                                    projectRecordName: projectRecordName) { }
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.appAccent)
                }
            }
        }
        .alert("出错了", isPresented: .constant(vm.errorMessage != nil)) {
            Button("好") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .task { await vm.load(projectRecordName: projectRecordName) }
        // 画板保存后返回时刷新
        .onAppear { Task { await vm.load(projectRecordName: projectRecordName) } }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.split.2x1.fill")
                .font(.system(size: 44))
                .foregroundColor(.appAccent)
            Text("还没有排料方案")
                .font(.appTitle)
                .foregroundColor(.appText)
            Text("点右上角 ＋ 新建一个方案，画板里排好裁片后可保存。")
                .font(.appBody)
                .foregroundColor(.appSubText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var layoutList: some View {
        List {
            ForEach(vm.layouts) { layout in
                NavigationLink {
                    LayoutBoardView(editingLayout: layout,
                                    projectRecordName: nil) { }
                } label: {
                    LayoutRow(layout: layout)
                }
            }
            .onDelete { idx in
                Task {
                    for index in idx { await vm.delete(vm.layouts[index]) }
                }
            }
        }
    }
}

// MARK: - 方案行
struct LayoutRow: View {
    let layout: LayoutItem

    var body: some View {
        HStack(spacing: 12) {
            // 缩略图
            if let url = layout.coverURL, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipped()
                    .cornerRadius(8)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.appCard)
                    Image(systemName: "square.split.2x1.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.appAccent.opacity(0.6))
                }
                .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(layout.title)
                    .font(.appHeadline)
                    .foregroundColor(.appText)
                Text(layout.previewText)
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
                Text(layout.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundColor(.appSubText)
            }
        }
        .padding(.vertical, 4)
    }
}
