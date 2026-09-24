//
//  CommonViews.swift
//  裁缝助手 —— 共享 UI 组件
//

import SwiftUI

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
