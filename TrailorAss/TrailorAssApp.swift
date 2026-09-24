//
//  TrailorAssApp.swift
//  裁缝助手 —— App 入口（PRD：SwiftUI 生命周期，1.0 强制浅色）
//

import SwiftUI

@main
struct TrailorAssApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.light)
        }
    }
}
