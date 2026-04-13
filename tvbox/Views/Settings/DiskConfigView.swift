import SwiftUI

struct DiskConfigView: View {
    @State private var config = DiskConfig()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section("阿里云盘") {
                TextField("Refresh Token", text: $config.aliToken)
                    .autocorrectionDisabled()
            }
            
            Section("夸克网盘") {
                TextField("Cookie", text: $config.quarkCookie)
                    .autocorrectionDisabled()
            }
            
            Section("115网盘") {
                TextField("Cookie", text: $config.pan115Cookie)
                    .autocorrectionDisabled()
            }
            
            Section("天翼云盘") {
                TextField("Refresh Token", text: $config.tianyiToken)
                    .autocorrectionDisabled()
            }
            
            Section("AList") {
                TextField("服务地址", text: $config.alistUrl)
                    .autocorrectionDisabled()
                TextField("访问Token", text: $config.alistToken)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("网盘配置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    NodeJSBridge.shared.saveDiskConfig(config)
                    dismiss()
                }
            }
        }
        .onAppear {
            config = NodeJSBridge.shared.loadDiskConfig()
        }
    }
}
