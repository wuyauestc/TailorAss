//
//  HomeTabView.swift
//  裁缝助手 —— 首页：9 个工具入口网格 + 最近项目摘要 + 图纸库入口
//

import SwiftUI

/// 首页工具点击去向：push 二级页 或 切换 Tab
enum ToolDestination: Hashable {
    case route(HomeRoute)
    case tab(MainTabView.Tab)
}

/// 首页二级页路由
enum HomeRoute: Hashable {
    case fabricCalc, unitConvert, shrinkage
    case seamAllowance, stitchDensity
    case needleThread, ironingTemp
    case layoutBoard
}

struct HomeTabView: View {
    let switchTab: (MainTabView.Tab) -> Void

    @State private var recentProjects: [ProjectItem] = []
    @State private var projectsLoaded = false

    private let tools: [ToolEntry] = [
        .init(name: "布料用量", icon: "scissors", destination: .route(.fabricCalc)),
        .init(name: "布料排料", icon: "square.split.2x1.fill", destination: .route(.layoutBoard)),
        .init(name: "单位换算", icon: "arrow.left.arrow.right", destination: .route(.unitConvert)),
        .init(name: "缩水率", icon: "drop", destination: .route(.shrinkage)),
        .init(name: "缝份换算", icon: "ruler", destination: .route(.seamAllowance)),
        .init(name: "针距换算", icon: "circle.grid.cross", destination: .route(.stitchDensity)),
        .init(name: "针线搭配", icon: "tray.full", destination: .route(.needleThread)),
        .init(name: "熨烫温度", icon: "flame", destination: .route(.ironingTemp)),
        .init(name: "版型图纸", icon: "square.grid.2x2.fill", destination: .tab(.patterns)),
        .init(name: "我的项目", icon: "folder.fill", destination: .tab(.projects))
    ]

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 9 宫格工具入口
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(tools) { tool in
                            switch tool.destination {
                            case .tab(let tab):
                                Button { switchTab(tab) } label: { ToolCell(tool: tool) }
                                    .buttonStyle(.plain)
                            case .route(let route):
                                NavigationLink(value: route) { ToolCell(tool: tool) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // 最近项目摘要（M3 接入私有库数据）
                    CardContainer {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("最近项目")
                                    .font(.appHeadline)
                                    .foregroundColor(.appText)
                                Spacer()
                                Button("查看全部") { switchTab(.projects) }
                                    .font(.appCaption)
                                    .foregroundColor(.appAccent)
                            }
                            if recentProjects.isEmpty {
                                Button { switchTab(.projects) } label: {
                                    Text("暂无项目，去创建第一个吧～")
                                        .font(.appBody)
                                        .foregroundColor(.appSubText)
                                }
                                .buttonStyle(.plain)
                            } else {
                                ForEach(recentProjects.prefix(3)) { p in
                                    Button { switchTab(.projects) } label: {
                                        HStack {
                                            Image(systemName: p.status.iconName)
                                                .foregroundColor(.appAccent)
                                                .font(.caption)
                                            Text(p.title)
                                                .font(.appBody)
                                                .foregroundColor(.appText)
                                            Spacer()
                                            Text(p.status.rawValue)
                                                .font(.appCaption)
                                                .foregroundColor(.appSubText)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color.appBackground)
            .navigationTitle(AppConstants.appName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .fabricCalc:    FabricCalcView()
                case .unitConvert:   UnitConvertView()
                case .shrinkage:     ShrinkageView()
                case .seamAllowance: SeamAllowanceView()
                case .stitchDensity: StitchDensityView()
                case .needleThread:  NeedleThreadView()
                case .ironingTemp:   IroningTempView()
                case .layoutBoard:   LayoutBoardView()
                }
            }
            .task {
                guard !projectsLoaded else { return }
                projectsLoaded = true
                do {
                    recentProjects = try await ProjectStoreFactory.projectStore.fetchProjects()
                } catch {
                    // 首页静默失败，不弹错误
                    recentProjects = []
                }
            }
        }
    }
}

// MARK: - 工具入口模型与单元格
struct ToolEntry: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let destination: ToolDestination
}

struct ToolCell: View {
    let tool: ToolEntry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: tool.icon)
                .font(.system(size: 28))
                .foregroundColor(.appAccent)
                .frame(height: 44)
            Text(tool.name)
                .font(.appBody)
                .foregroundColor(.appText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.appCard)
        .cornerRadius(AppStyle.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: AppStyle.cardShadowRadius,
                x: 0, y: AppStyle.cardShadowY)
    }
}
