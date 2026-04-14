import SwiftUI

struct DiskConfigView: View {
    @State private var config = DiskConfig()
    @State private var showToast = false
    @State private var toastMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionCard(title: "阿里云盘") {
                    VStack(spacing: 0) {
                        TextFieldRow(
                            icon: "doc.text.magnifyingglass",
                            title: "Refresh Token",
                            placeholder: "输入你的阿里云盘 refresh_token",
                            text: $config.aliToken
                        )
                    }
                }
                
                SectionCard(title: "夸克网盘") {
                    VStack(spacing: 0) {
                        TextFieldRow(
                            icon: "doc.text.magnifyingglass",
                            title: "Cookie",
                            placeholder: "输入你的夸克网盘 Cookie",
                            text: $config.quarkCookie,
                            isMultiline: true
                        )
                    }
                }
                
                SectionCard(title: "115 网盘") {
                    VStack(spacing: 0) {
                        TextFieldRow(
                            icon: "doc.text.magnifyingglass",
                            title: "Cookie",
                            placeholder: "输入你的 115 网盘 Cookie",
                            text: $config.pan115Cookie,
                            isMultiline: true
                        )
                    }
                }
                
                SectionCard(title: "天翼云盘") {
                    VStack(spacing: 0) {
                        TextFieldRow(
                            icon: "doc.text.magnifyingglass",
                            title: "Refresh Token",
                            placeholder: "输入你的天翼云盘 refresh_token",
                            text: $config.tianyiToken
                        )
                    }
                }
                
                SectionCard(title: "AList") {
                    VStack(spacing: 0) {
                        TextFieldRow(
                            icon: "link",
                            title: "服务地址",
                            placeholder: "http://xxx.com:5244",
                            text: $config.alistUrl
                        )
                        
                        Divider()
                        
                        TextFieldRow(
                            icon: "key",
                            title: "Token",
                            placeholder: "输入你的 AList Token",
                            text: $config.alistToken
                        )
                    }
                }
                
                SectionCard(title: "直播源") {
                    VStack(spacing: 0) {
                        TextFieldRow(
                            icon: "tv",
                            title: "直播源地址",
                            placeholder: "输入你的直播源 m3u8 地址",
                            text: $config.liveUrl
                        )
                    }
                }
                
                // 保存按钮
                Button(action: saveConfig) {
                    Text("保存配置")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.tint)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .navigationTitle("网盘配置")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.background)
        .toast(isPresented: $showToast, message: toastMessage)
        .onAppear {
            // 加载现有配置
            self.config = NodeJSBridge.shared.diskConfig
        }
    }
    
    private func saveConfig() {
        NodeJSBridge.shared.saveConfig(config)
        toastMessage = "配置已保存"
        showToast = true
    }
}

// MARK: - TextFieldRow
struct TextFieldRow: View {
    let icon: String
    let title: String
    let placeholder: String
    @Binding var text: String
    var isMultiline: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.tint)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondaryLabel)
                
                if isMultiline {
                    TextEditor(text: $text)
                        .frame(minHeight: 80)
                        .placeholder(when: text.isEmpty) {
                            Text(placeholder)
                                .foregroundColor(.tertiaryLabel)
                        }
                } else {
                    TextField(placeholder, text: $text)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
