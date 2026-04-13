import SwiftUI

@main
struct tvboxApp: App {
    @StateObject private var appConfig = AppConfig()
    @StateObject private var networkMonitor = NetworkMonitor()
    
    init() {
        // 启动Node.js桥接服务
        NodeJSBridge.shared.start()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appConfig)
                .environmentObject(networkMonitor)
        }
    }
}
