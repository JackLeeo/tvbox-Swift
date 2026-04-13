
import SwiftUI

struct DiskConfigView: View {
    @State private var aliToken: String = ""
    @State private var quarkCookie: String = ""
    @State private var pan115Cookie: String = ""
    @State private var tianyiToken: String = ""
    @State private var alistUrl: String = ""
    @State private var alistToken: String = ""
    @State private var liveUrl: String = ""
    @State private var showSaveSuccess = false
    
    var body: some View {
        Form {
            Section(header: Text("阿里云盘配置")) {
                TextField("Refresh Token", text: $aliToken)
                    .autocorrectionDisabled()
                Link("如何获取Token？", destination: URL(string: "https://xxx.com")!)
            }
            Section(header: Text("夸克网盘配置")) {
                TextField("Cookie", text: $quarkCookie)
                    .autocorrectionDisabled()
                Link("如何获取Cookie？", destination: URL(string: "https://xxx.com")!)
            }
            Section(header: Text("115网盘配置")) {
                TextField("Cookie", text: $pan115Cookie)
                    .autocorrectionDisabled()
            }
            Section(header: Text("天翼云盘配置")) {
                TextField("Refresh Token", text: $tianyiToken)
                    .autocorrectionDisabled()
            }
            Section(header: Text("AList配置")) {
                TextField("服务地址", text: $alistUrl)
                TextField("访问Token", text: $alistToken)
                    .autocorrectionDisabled()
            }
            Section(header: Text("直播源配置")) {
                TextField("直播源地址", text: $liveUrl)
            }
            Section {
                Button("保存配置") {
                    saveConfig()
                }
            }
        }
        .navigationTitle("网盘配置")
        .alert("保存成功", isPresented: $showSaveSuccess) {
            Button("确定", role: .cancel) {}
        }
        .onAppear {
            loadConfig()
        }
    }
    
    private func loadConfig() {
        let config = NodeJSBridge.shared.loadDiskConfig()
        aliToken = config.aliToken
        quarkCookie = config.quarkCookie
        pan115Cookie = config.pan115Cookie
        tianyiToken = config.tianyiToken
        alistUrl = config.alistUrl
        alistToken = config.alistToken
        liveUrl = config.liveUrl
    }
    
    private func saveConfig() {
        var config = DiskConfig()
        config.aliToken = aliToken
        config.quarkCookie = quarkCookie
        config.pan115Cookie = pan115Cookie
        config.tianyiToken = tianyiToken
        config.alistUrl = alistUrl
        config.alistToken = alistToken
        config.liveUrl = liveUrl
        
        NodeJSBridge.shared.saveDiskConfig(config)
        // 重新加载源，让配置生效
        if let path = Bundle.main.path(forResource: "asset/js", inDirectory: "tvbox/Resources") {
            NodeJSBridge.shared.loadRemoteSource(path: path)
        }
        showSaveSuccess = true
    }
}
