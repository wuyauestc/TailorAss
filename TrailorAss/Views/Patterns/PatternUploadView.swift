import SwiftUI
import PhotosUI
import UIKit

// MARK: - 上传图纸
struct PatternUploadView: View {
    @StateObject private var vm = PatternUploadViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloudKitService: CloudKitService

    @State private var photoItem: PhotosPickerItem?
    @State private var showDocumentPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("图纸标题", text: $vm.title)
                    Picker("分类", selection: $vm.category) {
                        ForEach(vm.categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                }

                Section("封面图（宽 ≤750px 自动压缩）") {
                    if let image = vm.coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 160)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("选择封面图", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: photoItem) { _, newItem in
                        guard let item = newItem else { return }
                        item.loadTransferable(type: Data.self) { result in
                            if case .success(let data?) = result, let img = UIImage(data: data) {
                                DispatchQueue.main.async { vm.coverImage = img }
                            }
                        }
                    }
                }

                Section("PDF 图纸（≤20MB）") {
                    if let data = vm.pdfData {
                        Label("已选择 PDF（\(data.count / 1024) KB）", systemImage: "doc.text.fill")
                            .foregroundColor(.appAccent)
                    }
                    Button { showDocumentPicker = true } label: {
                        Label("选择 PDF 文件", systemImage: "doc.badge.plus")
                    }
                }

                if let err = vm.errorMessage {
                    Text(err).foregroundColor(.red)
                }

                Section {
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        HStack {
                            if vm.isUploading { ProgressView() }
                            Text("提交上传")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!vm.canSubmit || vm.isUploading)
                }
            }
            .navigationTitle("上传图纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { url in
                    if let data = try? Data(contentsOf: url) {
                        vm.pdfData = data
                    }
                }
            }
            .onChange(of: vm.uploadSuccess) { _, success in
                if success { dismiss() }
            }
        }
    }
}

// MARK: - UIDocumentPicker 封装
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                // 需请求访问权限
                if url.startAccessingSecurityScopedResource() {
                    parent.onPick(url)
                    url.stopAccessingSecurityScopedResource()
                } else {
                    parent.onPick(url)
                }
            }
        }
    }
}
