//
//  CommonViews.swift
//  裁缝助手 —— 共享 UI 组件
//

import SwiftUI
import UIKit

/// 标题 + 数字输入框 + 单位 的表单行
struct LabeledField: View {
    let title: String
    @Binding var text: String
    let unit: String

    var body: some View {
        HStack {
            Text(title)
                .font(.appBody)
                .foregroundColor(.appText)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.appBody)
            Text(unit)
                .font(.appBody)
                .foregroundColor(.appSubText)
        }
    }
}

/// 米白背景修饰（隐藏 Form 默认背景）
struct AppBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
    }
}

extension View {
    func appBackground() -> some View { modifier(AppBackgroundModifier()) }
}

/// 卡片式白色容器
struct CardContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding()
            .background(Color.appCard)
            .cornerRadius(AppStyle.cornerRadius)
            .shadow(color: .black.opacity(0.05), radius: AppStyle.cardShadowRadius,
                    x: 0, y: AppStyle.cardShadowY)
    }
}

/// 结果行（标题 + 值）
struct ResultRow: View {
    let title: String
    let value: String
    var highlight = false

    var body: some View {
        HStack {
            Text(title)
                .font(.appBody)
                .foregroundColor(.appText)
            Spacer()
            Text(value)
                .font(highlight ? .appHeadline : .appBody)
                .foregroundColor(highlight ? .appAccent : .appText)
        }
    }
}

/// 本地文件 URL 图片（CKAsset 解出的临时文件同样适用）；后台加载避免卡主线程
struct LocalFileImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Color.appDivider
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(.appSubText)
                }
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            let loaded = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path)
            }.value
            image = loaded
        }
    }
}

/// 心形收藏按钮（列表卡片使用）
struct FavoriteHeartButton: View {
    let isFavorited: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .font(.system(size: 16))
                .foregroundColor(isFavorited ? .appAccent : .appSubText)
        }
        .buttonStyle(.plain)
    }
}

/// "请登录 iCloud" 引导弹窗（复用）
struct ICloudGuideAlertModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert("需要登录 iCloud", isPresented: $isPresented) {
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("浏览图纸无需登录；收藏与上传需要在系统「设置」中登录 iCloud。")
        }
    }
}

extension View {
    func iCloudGuideAlert(isPresented: Binding<Bool>) -> some View {
        modifier(ICloudGuideAlertModifier(isPresented: isPresented))
    }
}
