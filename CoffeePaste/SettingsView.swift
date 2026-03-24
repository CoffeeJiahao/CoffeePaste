import SwiftUI

struct SettingsView: View {
    @AppStorage("maxItems") private var maxItems = 200
    @AppStorage("isMaxItemsInfinite") private var isMaxItemsInfinite = false
    
    @AppStorage("maxDays") private var maxDays = 30
    @AppStorage("isMaxDaysInfinite") private var isMaxDaysInfinite = false

    var body: some View {
        Form {
            Section(header: Text("存储限制")) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("无限数量上限", isOn: $isMaxItemsInfinite)
                    
                    if !isMaxItemsInfinite {
                        HStack {
                            Text("最大记录数:")
                            TextField("", value: $maxItems, formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Stepper("", value: $maxItems, in: 10...5000, step: 10)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 4)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("无限存储时间", isOn: $isMaxDaysInfinite)
                    
                    if !isMaxDaysInfinite {
                        HStack {
                            Text("最长保存天数:")
                            TextField("", value: $maxDays, formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Stepper("", value: $maxDays, in: 1...365)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 300)
        .navigationTitle("设置")
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isMaxItemsInfinite)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isMaxDaysInfinite)
    }
}
