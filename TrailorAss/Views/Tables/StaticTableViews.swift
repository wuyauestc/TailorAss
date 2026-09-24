import SwiftUI

// MARK: - 5.6 针线搭配表（静态查询）
struct NeedleThreadView: View {
    var body: some View {
        List {
            ForEach(StaticTableData.needleThreadTable) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.fabricType)
                        .font(.appHeadline)
                        .foregroundColor(.appText)
                    HStack {
                        Label(item.needle, systemImage: "circle.grid.cross")
                        Spacer()
                        Label(item.thread, systemImage: "tray.full")
                    }
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("针线搭配表")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }
}

// MARK: - 5.7 熨烫温度表（静态查询）
struct IroningTempView: View {
    var body: some View {
        List {
            ForEach(StaticTableData.ironingTempTable) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.fabricType)
                            .font(.appHeadline)
                            .foregroundColor(.appText)
                        Text(item.remark)
                            .font(.appCaption)
                            .foregroundColor(.appSubText)
                    }
                    Spacer()
                    Text(item.temperature)
                        .font(.appHeadline)
                        .foregroundColor(.appAccent)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("熨烫温度表")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }
}
