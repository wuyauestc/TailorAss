import SwiftUI

// MARK: - 图纸库列表
struct PatternsTabView: View {
    @StateObject private var vm = PatternsViewModel()
    @State private var showUpload = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部分类筛选
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AppConstants.PatternCategory.allCases, id: \.self) { cat in
                            Button {
                                vm.selectedCategory = cat.rawValue
                                Task { await vm.load(reset: true) }
                            } label: {
                                Text(cat.rawValue)
                                    .font(.appBody)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(vm.selectedCategory == cat.rawValue ? Color.appAccent : Color.appCard)
                                    .foregroundColor(vm.selectedCategory == cat.rawValue ? .white : .appText)
                                    .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)

                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.appSubText)
                    TextField("搜索图纸标题", text: $vm.searchKeyword)
                        .onSubmit {
                            Task { await vm.load(reset: true) }
                        }
                }
                .padding(10)
                .background(Color.appCard)
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom, 8)

                // 网格列表
                ScrollView {
                    if vm.isLoading && vm.patterns.isEmpty {
                        ProgressView().padding()
                    } else if vm.patterns.isEmpty {
                        Text("暂无图纸")
                            .foregroundColor(.appSubText)
                            .padding()
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(vm.patterns) { pattern in
                                NavigationLink {
                                    PatternDetailView(pattern: pattern)
                                } label: {
                                    PatternCard(pattern: pattern)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    if let err = vm.errorMessage {
                        Text(err).foregroundColor(.red).padding()
                    }
                }
            }
            .navigationTitle("版型图纸")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.appBackground)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showUpload = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.appAccent)
                    }
                }
            }
            .sheet(isPresented: $showUpload) {
                PatternUploadView()
            }
            .task { await vm.load() }
        }
    }
}

struct PatternCard: View {
    let pattern: Pattern
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = pattern.coverURL, let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .clipped()
                    .cornerRadius(AppStyle.cornerRadius)
            } else {
                Rectangle()
                    .fill(Color.appDivider)
                    .frame(height: 140)
                    .cornerRadius(AppStyle.cornerRadius)
                    .overlay(Image(systemName: "photo").foregroundColor(.appSubText))
            }
            Text(pattern.title)
                .font(.appBody)
                .foregroundColor(.appText)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").foregroundColor(.appAccent).font(.caption)
                Text("\(pattern.favoritesCount)").font(.appCaption).foregroundColor(.appSubText)
                Spacer()
                Text(pattern.category).font(.appCaption).foregroundColor(.appSubText)
            }
        }
        .padding(10)
        .background(Color.appCard)
        .cornerRadius(AppStyle.cornerRadius)
    }
}
