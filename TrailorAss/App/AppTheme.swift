//
//  AppTheme.swift
//  裁缝助手 —— 全局主题（PRD 样式约束：浅色，米白 #F7F3EC + 焦糖 #B98A5A，正文 ≥15pt）
//

import SwiftUI

extension Color {
    /// 主色：米白 #F7F3EC（背景）
    static let appBackground = Color(red: 0xF7 / 255, green: 0xF3 / 255, blue: 0xEC / 255)
    /// 主色：焦糖 #B98A5A（强调色）
    static let appAccent = Color(red: 0xB9 / 255, green: 0x8A / 255, blue: 0x5A / 255)
    /// 正文：深灰 #333333
    static let appText = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)
    /// 次级文字
    static let appSubText = Color(red: 0x88 / 255, green: 0x88 / 255, blue: 0x88 / 255)
    /// 卡片背景
    static let appCard = Color.white
    /// 分割线
    static let appDivider = Color(red: 0xE5 / 255, green: 0xE0 / 255, blue: 0xD6 / 255)
}

extension Font {
    static let appTitle = Font.system(size: 22, weight: .semibold)
    static let appHeadline = Font.system(size: 17, weight: .semibold)
    static let appBody = Font.system(size: 15)   // 正文不小于 15pt
    static let appCaption = Font.system(size: 13)
}

enum AppStyle {
    static let cornerRadius: CGFloat = 12
    static let cardShadowRadius: CGFloat = 4
    static let cardShadowY: CGFloat = 2
}
