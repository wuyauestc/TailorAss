//
//  MainTabView.swift
//  裁缝助手 —— 主导航（PRD：TabView 4 个 Tab）
//

import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable {
        case home, patterns, projects, mine
    }

    @State private var selectedTab: Tab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTabView(switchTab: { selectedTab = $0 })
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(Tab.home)

            PatternsTabView()
                .tabItem { Label("图纸", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.patterns)

            ProjectsTabView()
                .tabItem { Label("项目", systemImage: "folder.fill") }
                .tag(Tab.projects)

            MineTabView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(Tab.mine)
        }
        .tint(.appAccent)
    }
}
