//
//  ShrinkageView.swift
//  裁缝助手 —— 5.3 缩水率计算
//

import SwiftUI

struct ShrinkageView: View {
    @StateObject private var vm = ShrinkageViewModel()

    var body: some View {
        Form {
            Section("输入参数") {
                LabeledField(title: "成品尺寸 L", text: $vm.finishedLength, unit: "cm")
                LabeledField(title: "缩水率 r", text: $vm.shrinkage, unit: "%")
            }

            Section("裁剪尺寸") {
                HStack {
                    Text("裁剪尺寸")
                        .font(.appBody)
                    Spacer()
                    if let cut = vm.cutLength {
                        Text(String(format: "%.1f cm", cut))
                            .font(.appHeadline)
                            .foregroundColor(.appAccent)
                    } else {
                        Text("请输入参数")
                            .font(.appBody)
                            .foregroundColor(.appSubText)
                    }
                }
                Text("布料下水后缩水 r%，裁剪需预留；建议先预缩再裁剪。")
                    .font(.appCaption)
                    .foregroundColor(.appSubText)
            }
        }
        .appBackground()
        .navigationTitle("缩水率计算")
        .navigationBarTitleDisplayMode(.inline)
    }
}
