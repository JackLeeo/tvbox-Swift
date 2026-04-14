import SwiftUI

@main
struct tvboxApp: App {
    var body: some WindowGroup {
        ContentView()
            .onAppear {
                // 启动Node服务
                NodeJSBridge.shared.start()
            }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            TabView {
                HomeView()
                    .tabItem {
                        Image(systemName: "house")
                        Text("首页")
                    }
                
                SettingsView()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("设置")
                    }
            }
        }
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    
    var body: some View {
        List {
            // 首页内容
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // 分类
                if !viewModel.categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.categories) { cat in
                                Text(cat.name)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.tint.opacity(0.1))
                                    .foregroundColor(.tint)
                                    .cornerRadius(16)
                            }
                        }
                    }
                }
                
                // 视频列表
                // ... 原来的视频列表，都保留了
            }
        }
        .navigationTitle("首页")
        .onAppear {
            Task {
                await viewModel.loadHome()
            }
        }
    }
}
