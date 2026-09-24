import SwiftUI

// MARK: - 首页：9 个工具入口网格 + 最近项目摘要 + 图纸库入口
struct HomeTabView: View {
    @StateObject private var projectsVM = ProjectsViewModel()
    let switchTab: (MainTabView.Tab) -> Void

    private let tools: [ToolEntry] = [
        ToolEntry(name: "布料用量", icon: "scissors", color: .appAccent, destination: .fabricCalc),
        ToolEntry(name: "单位换算", icon: "arrow.left.arrow.right", color: .appAccent, destination: .unitConvert),
        ToolEntry(name: "缩水率", icon: "drop", color: .appAccent, destination: .shrinkage),
        ToolEntry(name: "缝份换算", icon: "ruler", color: .appAccent, destination: .seamAllowance),
        ToolEntry(name: "针距换算", icon: "circle.grid.cross", color: .appAccent, destination: .stitchDensity),
        ToolEntry(name: "针线搭配", icon: "tray.full", color: .appAccent, destination: .needleThread),
        ToolEntry(name: "熨烫温度", icon: "flame", color: .appAccent, destination: .ironingTemp),
        ToolEntry(name: "版型图纸", icon: "square.grid.2x2.fill", color: .appAccent, destination: .switchTab(.patterns)),
        ToolEntry(name: "我的项目", icon: "folder.fill", color: .appAccent, destination: .switchTab(.projects))
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
                            case .switchTab(let tab):
                                Button { switchTab(tab) } label: { ToolCell(tool: tool) }
                                    .buttonStyle(.plain)
                            default:
                                NavigationLink(value: tool.destination) {
                                    ToolCell(tool: tool)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // 最近项目摘要
                    VStack(alignment: .leading, spacing: 12) {
                        Text("最近项目")
                            .font(.appHeadline)
                            .foregroundColor(.appText)
                        if projectsVM.projects.isEmpty {
                            Text("暂无项目，去创建第一个吧～")
                                .font(.appBody)
                                .foregroundColor(.appSubText)
                        } else {
                            ForEach(projectsVM.projects.prefix(3)) { project in
                                NavigationLink(value: NavigationDestination.projectDetail(project)) {
                                    RecentProjectRow(project: project)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                    .background(Color.appCard)
                    .cornerRadius(AppStyle.cornerRadius)
                    .shadow(color: .black.opacity(0.05), radius: AppStyle.cardShadowRadius, x: 0, y: AppStyle.cardShadowY)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(AppConstants.appName)
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.appBackground)
            .navigationDestination(for: NavigationDestination.self) { dest in
                destinationView(for: dest)
            }
            .task { await projectsVM.load() }
        }
    }

    @ViewBuilder
    private func destinationView(for dest: NavigationDestination) -> some View {
        switch dest {
        case .fabricCalc: FabricCalcView()
        case .unitConvert: UnitConvertView()
        case .shrinkage: ShrinkageView()
        case .seamAllowance: SeamAllowanceView()
        case .stitchDensity: StitchDensityView()
        case .needleThread: NeedleThreadView()
        case .ironingTemp: IroningTempView()
        case .projectDetail(let p): ProjectDetailView(project: p)
        case .switchTab: EmptyView() // 由 switchTab 闭包处理
        }
    }
}

// MARK: - 工具入口模型
struct ToolEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let destination: NavigationDestination
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
        .shadow(color: .black.opacity(0.05), radius: AppStyle.cardShadowRadius, x: 0, y: AppStyle.cardShadowY)
    }
}

struct RecentProjectRow: View {
    let project: SewingProject
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.appBody)
                    .foregroundColor(.appText)
                Text(project.status.displayName)
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.appSubText)
        }
    }
}

// MARK: - 导航路由
enum NavigationDestination: Hashable {
    case fabricCalc
    case unitConvert
    case shrinkage
    case seamAllowance
    case stitchDensity
    case needleThread
    case ironingTemp
    case switchTab(MainTabView.Tab)
    case projectDetail(SewingProject)
}
