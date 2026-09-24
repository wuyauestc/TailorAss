//
//  StaticTableViews.swift
//  裁缝助手 —— 5.6 针线搭配表 / 5.7 熨烫温度表（静态查询，纯本地数据）
//

import SwiftUI

// MARK: - 5.6 针线搭配表
struct NeedleThreadView: View {
    var body: some View {
        List {
            Section {
                ForEach(StaticTableData.needleThreadTable) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.fabricType)
                            .font(.appHeadline)
                            .foregroundColor(.appText)
                        HStack(spacing: 12) {
                            TagView(text: "机针：\(item.needle)")
                            TagView(text: "线：\(item.thread)")
                        }
                    }
                    .listRowBackground(Color.appCard)
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("根据布料厚薄与弹性选择合适的机针与缝线。")
            }
        }
        .appBackground()
        .navigationTitle("针线搭配表")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 5.7 熨烫温度表
struct IroningTempView: View {
    var body: some View {
        List {
            Section {
                ForEach(StaticTableData.ironingTempTable) { item in
                    HStack(spacing: 12) {
                        Text(item.fabricType)
                            .font(.appBody)
                            .foregroundColor(.appText)
                        Spacer()
                        Text(item.temperature)
                            .font(.appHeadline)
                            .foregroundColor(.appAccent)
                            .frame(width: 70, alignment: .trailing)
                        Text(item.remark)
                            .font(.appCaption)
                            .foregroundColor(.appSubText)
                            .frame(width: 130, alignment: .leading)
                    }
                    .listRowBackground(Color.appCard)
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("熨烫前请先确认布料成分；不确定时先低温试烫布料边角。")
            }
        }
        .appBackground()
        .navigationTitle("熨烫温度表")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 标签组件
private struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.appCaption)
            .foregroundColor(.appAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.appAccent.opacity(0.12))
            .cornerRadius(8)
    }
}
