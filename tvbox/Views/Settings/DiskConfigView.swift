import SwiftUI

struct DiskConfigView: View {
    @State private var aliToken = ""
    @State private var quarkCookie = ""
    @State private var pan115Cookie = ""
    @State private var tianyiToken = ""
    @State private var alistUrl = ""
    @State private var alistToken = ""
    @State private var liveUrl = ""
    
    @State private var showToast = false
    @State private var toastMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                SectionCard(title: "阿里云盘") {
                    TextField("Refresh Token", text: $aliToken)
                }
                
                SectionCard(title: "夸克网盘") {
                    TextField("Cookie", text: $quarkCookie)
                }
                
                SectionCard(title: "115 网盘") {
                    TextField("Cookie", text: $pan115Cookie)
                }
                
                SectionCard(title: "天翼云盘") {
                    TextField("Refresh Token", text: $tianyiToken)
                }
                
                SectionCard(title: "AList") {
                    TextField("服务地址", text: $alistUrl)
                    TextField("访问 Token", text: $alistToken)
                }
                
                SectionCard(title: "直播源") {
                    TextField("直播源地址", text: $liveUrl)
                }
                
                Section {
                    Button("保存配置") {
                        saveConfig()
                    }
                }
            }
            .navigationTitle("网盘配置")
            .navigationBarTitleDisplayMode(.large)
            .toast(isPresented: $showToast, message: toastMessage)
            .background(Color.background)
            .onAppear {
                let defaults = UserDefaults.standard
                aliToken = defaults.string(forKey: "aliToken") ?? ""
                quarkCookie = defaults.string(forKey: "quarkCookie") ?? ""
                pan115Cookie = defaults.string(forKey: "pan115Cookie") ?? ""
                tianyiToken = defaults.string(forKey: "tianyiToken") ?? ""
                alistUrl = defaults.string(forKey: "alistUrl") ?? ""
                alistToken = defaults.string(forKey: "alistToken") ?? ""
                liveUrl = defaults.string(forKey: "liveUrl") ?? ""
            }
        }
    }
    
    private func saveConfig() {
        let config: [String: String] = [
            "aliToken": aliToken,
            "quarkCookie": quarkCookie,
            "pan115Cookie": pan115Cookie,
            "tianyiToken": tianyiToken,
            "alistUrl": alistUrl,
            "alistToken": alistToken,
            "liveUrl": liveUrl
        ]
        
        NodeJSBridge.shared.saveDiskConfig(config)
        
        toastMessage = "配置已保存"
        showToast = true
    }
}
