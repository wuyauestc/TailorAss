import SwiftUI
import PDFKit

// MARK: - 图纸详情
struct PatternDetailView: View {
    @StateObject private var vm: PatternDetailViewModel
    @EnvironmentObject private var cloudKitService: CloudKitService

    init(pattern: Pattern) {
        _vm = StateObject(wrappedValue: PatternDetailViewModel(pattern: pattern))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 封面大图
                if let url = vm.pattern.coverURL, let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .cornerRadius(AppStyle.cornerRadius)
                }

                // 标题、作者、分类
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.pattern.title)
                        .font(.appTitle)
                        .foregroundColor(.appText)
                    HStack {
                        Text("作者：\(vm.pattern.creatorName)")
                        Spacer()
                        Text(vm.pattern.category)
                    }
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
                }

                // 收藏按钮
                Button {
                    guard cloudKitService.isICloudAvailable else { return }
                    Task { await vm.toggleFavorite() }
                } label: {
                    HStack {
                        Image(systemName: vm.isFavorited ? "heart.fill" : "heart")
                        Text(vm.isFavorited ? "已收藏" : "收藏")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(vm.isFavorited ? Color.appCard : Color.appAccent)
                    .foregroundColor(vm.isFavorited ? .appAccent : .white)
                    .cornerRadius(AppStyle.cornerRadius)
                    .overlay(RoundedRectangle(cornerRadius: AppStyle.cornerRadius).stroke(Color.appAccent, lineWidth: 1))
                }
                .disabled(!cloudKitService.isICloudAvailable)

                if !cloudKitService.isICloudAvailable {
                    Text("请先在系统设置中登录 iCloud 后再收藏")
                        .font(.appCaption)
                        .foregroundColor(.orange)
                }

                // PDF 预览
                if let pdfURL = vm.pattern.pdfURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("图纸预览")
                            .font(.appHeadline)
                            .foregroundColor(.appText)
                        PDFPreviewView(url: pdfURL)
                            .frame(height: 400)
                            .cornerRadius(AppStyle.cornerRadius)
                    }
                }

                if let err = vm.errorMessage {
                    Text(err).foregroundColor(.red)
                }
            }
            .padding()
        }
        .navigationTitle("图纸详情")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.appBackground)
        .task { await vm.checkFavorite() }
    }
}

// MARK: - PDFKit 预览封装
struct PDFPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
