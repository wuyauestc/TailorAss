import SwiftUI

struct GarmentPreviewLauncherView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = UnityGarmentPreview.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                switch preview.state {
                case .idle, .launching:
                    ProgressView("正在启动 3D 预览…").tint(.white)
                case .generating:
                    ProgressView("正在生成 T 恤…").tint(.white)
                case .completed(let result):
                    Label("生成完成 · \(result.elapsedMs) ms", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle).foregroundStyle(.yellow)
                    Text(message).multilineTextAlignment(.center).foregroundStyle(.white)
                    Button("关闭") { dismiss() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(28)
        }
        .task { preview.present(patternJSON: GarmentSamplePattern.json) }
        .onChange(of: preview.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
        .overlay(alignment: .topTrailing) {
            Button { preview.cancel() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title).symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .padding()
        }
    }
}
