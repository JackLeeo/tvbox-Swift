import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showDiskConfig = false
    @State private var showAddNodeSource = false
    
    var body: some View {
        Form {
            Section("源管理") {
                NavigationLink("添加Node源") {
                    AddNodeSourceView()
                }
            }
            
            Section("网盘配置") {
                NavigationLink("网盘配置") {
                    DiskConfigView()
                }
            }
            
            Section("通用设置") {
                // 原有设置项...
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
