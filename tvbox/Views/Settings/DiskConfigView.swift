import SwiftUI

struct DiskConfigView: View {
    @State private var aliToken: String = ""
    @State private var quarkCookie: String = ""
    @State private var pan115Cookie: String = ""
    @State private var tianyiToken: String = ""
    @State private var alistUrl: String = ""
    @State private var alistToken: String = ""
    @State private var liveUrl: String = ""
    
    @State private var showToast = false
    @State private var toastMessage = ""
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            SectionCard(title: "阿里云盘") {
                VStack(spacing: 0) {
                    TextEditor(text: $aliToken)
                        .placeholder(when: aliToken.isEmpty) {
                            Text("请输入阿里云盘 Refresh Token")
                                .foregroundColor(.secondaryLabel)
                        }
                        .frame(minHeight: 80)
                        .padding(12)
                }
            }
            
            SectionCard(title: "夸克网盘") {
                VStack(spacing: 0) {
                    TextEditor(text: $quarkCookie)
                        .placeholder(when: quarkCookie.isEmpty) {
                            Text("请输入夸克网盘 Cookie")
                                .foregroundColor(.secondaryLabel)
                        }
                        .frame(minHeight: 80)
                        .padding(12)
                }
            }
            
            SectionCard(title: "115 网盘") {
                VStack(spacing: 0) {
                    TextEditor(text: $pan115Cookie)
                        .placeholder(when: pan115Cookie.isEmpty) {
                            Text("请输入 115 网盘 Cookie")
                                .foregroundColor(.secondaryLabel)
                        }
                        .frame(minHeight: 80)
                        .padding(12)
                }
            }
            
            SectionCard(title: "天翼云盘") {
                VStack(spacing: 0) {
                    TextEditor(text: $tianyiToken)
                        .placeholder(when: tianyiToken.isEmpty) {
                            Text("请输入天翼云盘 Refresh Token")
                                .foregroundColor(.secondaryLabel)
                        }
                        .frame(minHeight: 80)
                        .padding(12)
                }
            }
            
            SectionCard(title: "AList") {
                VStack(spacing: 0) {
                    TextField("AList 服务地址", text: $alistUrl)
                        .padding(12)
                    
                    Divider()
                    
                    TextField("AList Token", text: $alistToken)
                        .padding(12)
                }
            }
            
            SectionCard(title: "直播源") {
                VStack(spacing: 0) {
                    TextField("直播源地址", text: $liveUrl)
                        .padding(12)
                }
            }
            
            Section {
                Button {
                    saveConfig()
                } label: {
                    Text("保存配置")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .background(Color.tint)
                        .cornerRadius(12)
                }
            }
        }
        .navigationTitle("网盘配置")
        .navigationBarTitleDisplayMode(.inline)
        .toast(isPresented: $showToast, message: toastMessage)
        .onAppear {
            loadConfig()
        }
    }
    
    private func loadConfig() {
        let config = NodeJSBridge.shared.diskConfig
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
        config.aliToken = aliToken.trimmingWhitespace()
        config.quarkCookie = quarkCookie.trimmingWhitespace()
        config.pan115Cookie = pan115Cookie.trimmingWhitespace()
        config.tianyiToken = tianyiToken.trimmingWhitespace()
        config.alistUrl = alistUrl.trimmingWhitespace()
        config.alistToken = alistToken.trimmingWhitespace()
        config.liveUrl = liveUrl.trimmingWhitespace()
        
        NodeJSBridge.shared.saveDiskConfig(config)
        
        toastMessage = "配置已保存"
        showToast = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismiss()
        }
    }
}
