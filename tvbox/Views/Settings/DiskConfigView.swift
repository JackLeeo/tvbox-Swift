import SwiftUI

struct DiskConfigView: View {
    @Environment(\.dismiss) var dismiss
    @State private var config: DiskConfig
    
    init() {
        _config = State(initialValue: NodeJSBridge.shared.getDiskConfig())
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("阿里云盘")) {
                    TextField("Refresh Token", text: $config.aliToken)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
                
                Section(header: Text("夸克网盘")) {
                    TextField("Cookie", text: $config.quarkCookie)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
                
                Section(header: Text("115网盘")) {
                    TextField("Cookie", text: $config.pan115Cookie)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
                
                Section(header: Text("天翼云盘")) {
                    TextField("Refresh Token", text: $config.tianyiToken)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
                
                Section(header: Text("AList")) {
                    TextField("服务地址", text: $config.alistUrl)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    
                    TextField("Token", text: $config.alistToken)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("网盘配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        NodeJSBridge.shared.saveDiskConfig(config)
                        
                        // 重新加载源，让配置生效
                        if let path = Bundle.main.path(forResource: "asset/js", ofType: nil) {
                            NodeJSBridge.shared.loadRemoteSource(path: path)
                        }
                        
                        dismiss()
                    }
                }
            }
        }
    }
}
