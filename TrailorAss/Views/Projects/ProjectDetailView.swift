import SwiftUI
import PhotosUI

// MARK: - 项目详情
struct ProjectDetailView: View {
    @StateObject private var vm: ProjectDetailViewModel
    @State private var showFabricCalc = false
    @State private var photoItems: [PhotosPickerItem] = []

    init(project: SewingProject) {
        _vm = StateObject(wrappedValue: ProjectDetailViewModel(project: project))
    }

    var body: some View {
        Form {
            // 状态流转：四态按钮组
            Section("项目状态") {
                HStack(spacing: 8) {
                    ForEach(AppConstants.ProjectStatus.allCases, id: \.self) { status in
                        let isCurrent = vm.project.status == status
                        let canSwitch = vm.project.status.canTransition(to: status)
                        Button {
                            vm.transition(to: status)
                        } label: {
                            Text(status.displayName)
                                .font(.appCaption)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(isCurrent ? Color.appAccent : (canSwitch ? Color.appCard : Color.appDivider))
                                .foregroundColor(isCurrent ? .white : (canSwitch ? .appText : .appSubText))
                                .cornerRadius(8)
                        }
                        .disabled(!canSwitch)
                    }
                }
            }

            // 基本信息
            Section("项目信息") {
                TextField("项目名称", text: $vm.project.title)
                    .onSubmit { Task { await vm.save() } }
            }

            // 材料清单 + 工具联动
            Section {
                HStack {
                    Text("材料清单").font(.appHeadline)
                    Spacer()
                    Button {
                        showFabricCalc = true
                    } label: {
                        Label("用布料计算器", systemImage: "scissors")
                            .font(.appCaption)
                    }
                }

                ForEach(vm.project.materials) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(String(format: "%.2f %@", item.qty, item.unit))
                            .foregroundColor(.appSubText)
                    }
                }
                .onDelete { vm.removeMaterial(at: $0) }

                Button {
                    vm.addMaterial(MaterialItem(name: "新材料", qty: 1, unit: "米"))
                } label: {
                    Label("添加材料", systemImage: "plus.circle")
                }
            }

            // 备注
            Section("备注") {
                TextEditor(text: $vm.project.notes)
                    .frame(minHeight: 80)
                    .onSubmit { Task { await vm.save() } }
            }

            // 照片
            Section("成品/过程照片") {
                if !vm.project.photoURLs.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(vm.project.photoURLs, id: \.self) { url in
                                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipped()
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
                PhotosPicker(selection: $photoItems, matching: .images) {
                    Label("添加照片", systemImage: "photo.on.rectangle.angled")
                }
                .onChange(of: photoItems) { _, items in
                    loadPhotos(items)
                }
            }

            if let err = vm.errorMessage {
                Text(err).foregroundColor(.red)
            }
        }
        .navigationTitle(vm.project.title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .sheet(isPresented: $showFabricCalc) {
            ProjectFabricCalcSheet()
                .environmentObject(vm)
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    images.append(img)
                }
            }
            if !images.isEmpty {
                await vm.uploadPhotos(images)
            }
            photoItems = []
        }
    }
}
