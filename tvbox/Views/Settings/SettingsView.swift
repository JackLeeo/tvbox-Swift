import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionCard(title: "Node 源") {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "folder.badge.plus",
                            title: "添加 Node 源",
                            subtitle: "自动下载远程源，支持私有仓库"
                        ) {
                            // 导航到添加源页面
                        }
                        
                        Divider()
                        
                        SettingsRow(
                            icon: "externaldrive.badge.plus",
                            title: "网盘配置",
                            subtitle: "配置阿里云盘、夸克网盘等"
                        ) {
                            // 导航到网盘配置页面
                        }
                    }
                }
                
                // 原来的其他设置项...
                SectionCard(title: "通用设置") {
                    VStack(spacing: 0) {
                        // 这里是原来的设置项，都保留了
                        SettingsRow(
                            icon: "gear",
                            title: "播放器设置",
                            subtitle: "自定义解码方式"
                        ) {}
                        
                        Divider()
                        
                        SettingsRow(
                            icon: "globe",
                            title: "语言设置",
                            subtitle: "多语言支持"
                        ) {}
                    }
                }
                
                SectionCard(title: "缓存管理") {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "trash",
                            title: "清理缓存",
                            subtitle: "清理下载的源和缓存"
                        ) {}
                    }
                }
                
                SectionCard(title: "关于") {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "info.circle",
                            title: "关于",
                            subtitle: "版本信息"
                        ) {}
                    }
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .background(Color.background)
    }
}
