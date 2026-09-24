import SwiftUI

// MARK: - 主导航 TabView（4 个 Tab）
struct MainTabView: View {
    @State private var selection: Tab = .home

    enum Tab: Hashable {
        case home, patterns, projects, mine
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeTabView(switchTab: { tab in selection = tab })
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
        .background(Color.appBackground.ignoresSafeArea())
    }
}
