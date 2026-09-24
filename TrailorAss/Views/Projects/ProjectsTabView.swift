import SwiftUI

// MARK: - 项目列表（按状态分组）
struct ProjectsTabView: View {
    @StateObject private var vm = ProjectsViewModel()
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if vm.isLoading && vm.projects.isEmpty {
                    ProgressView().padding()
                } else if vm.projects.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.appSubText)
                        Text("还没有项目，点击右上角创建")
                            .foregroundColor(.appSubText)
                    }
                    .padding(.top, 80)
                } else {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(vm.groupedByStatus, id: \.status) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.status.displayName)
                                    .font(.appHeadline)
                                    .foregroundColor(.appText)
                                    .padding(.horizontal)

                                ForEach(group.items) { project in
                                    NavigationLink {
                                        ProjectDetailView(project: project)
                                    } label: {
                                        ProjectRow(project: project)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }

                if let err = vm.errorMessage {
                    Text(err).foregroundColor(.red).padding()
                }
            }
            .navigationTitle("我的项目")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.appBackground)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.appAccent)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                ProjectCreateView()
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }
}

struct ProjectRow: View {
    let project: SewingProject
    var body: some View {
        HStack(spacing: 12) {
            if let firstURL = project.photoURLs.first,
               let data = try? Data(contentsOf: firstURL),
               let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipped()
                    .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appDivider)
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "scissors").foregroundColor(.appSubText))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.appBody)
                    .foregroundColor(.appText)
                Text("\(project.materials.count) 种材料 · \(project.status.displayName)")
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.appSubText)
        }
        .padding(12)
        .background(Color.appCard)
        .cornerRadius(AppStyle.cornerRadius)
    }
}
