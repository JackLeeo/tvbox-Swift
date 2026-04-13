import SwiftUI
@main
struct tvboxApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    // 启动 Node.js 服务
                    NodeJSBridge.shared.start()
                }
        }
    }
}
