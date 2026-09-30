//
//  PatternUploadView.swift
//  裁缝助手 —— 5.8 图纸上传：标题/分类/封面(PhotosPicker 压缩至 750px)/PDF(≤20MB)
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct PatternUploadView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = PatternUploadViewModel()
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("图纸信息") {
                    TextField("请输入标题", text: $vm.title)
                        .font(.appBody)
                    Picker("分类", selection: $vm.category) {
                        ForEach(PatternCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                }

                Section("封面图") {
                    PhotosPicker(selection: $vm.photoItem,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        if let cover = vm.coverImage {
                            Image(uiImage: cover)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 30))
                                Text("选择封面图")
                                    .font(.appBody)
                                Text("自动压缩至宽 750px")
                                    .font(.appCaption)
                                    .foregroundColor(.appSubText)
                            }
                            .foregroundColor(.appAccent)
                            .frame(width: 120, height: 160)
                            .background(Color.appAccent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                Section("PDF 图纸") {
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.pdfName ?? "选择 PDF 文件")
                                    .font(.appBody)
                                    .foregroundColor(vm.pdfName == nil ? .appAccent : .appText)
                                Text("文件大小不超过 20MB")
                                    .font(.appCaption)
                                    .foregroundColor(.appSubText)
                            }
                            Spacer()
                            if vm.pdfName != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    if let pdfError = vm.pdfError {
                        Text(pdfError)
                            .font(.appCaption)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button {
                        vm.submit()
                    } label: {
                        HStack {
                            if vm.submitting {
                                ProgressView().tint(.white)
                            }
                            Text(vm.submitting ? "上传中…" : "提交上传")
                                .font(.appHeadline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!vm.canSubmit)
                    .listRowBackground(vm.canSubmit ? Color.appAccent : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                }
            }
            .navigationTitle("上传图纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [UTType.pdf],
                          allowsMultipleSelection: false) { result in
                handleFileImporter(result)
            }
            .iCloudGuideAlert(isPresented: $vm.showICloudGuide)
            .alert("上传失败", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .alert("上传成功", isPresented: $vm.didSucceed) {
                Button("好的") {
                    dismiss()
                }
            } message: {
                Text("图纸已发布并自动加入你的收藏")
            }
        }
    }

    private func handleFileImporter(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        // fileImporter 返回安全域 URL，需要显式获取/释放访问权
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        vm.handlePickedPDF(url)
    }
}
