//
//  PlaceholderTabViews.swift
//  裁缝助手 —— 通用占位组件（项目/我的 Tab 已在各自文件实现）
//

import SwiftUI

// MARK: - 通用"敬请期待"占位
struct ComingSoonView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 44))
                .foregroundColor(.appAccent)
            Text(title)
                .font(.appTitle)
                .foregroundColor(.appText)
            Text(message)
                .font(.appBody)
                .foregroundColor(.appSubText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}
