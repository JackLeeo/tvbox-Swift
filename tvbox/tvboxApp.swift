import SwiftUI
import Combine

@main
struct tvboxApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var networkMonitor = NetworkMonitor.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(networkMonitor)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var apiConfig = ApiConfig.shared
    @Published var isConfigLoaded = false
    @Published var currentSourceKey: String = ""
    @Published var configLoadError: String?
    @Published var isRetryingConfig = false

    #if os(macOS)
    @Published var splitViewVisibility: NavigationSplitViewVisibility = .all
    private var splitViewVisibilityBeforePlayerFullScreen: NavigationSplitViewVisibility?
    #endif

    private var lastVodUrl: String = ""
    private var lastLiveUrl: String = ""
    private var networkRestoredCancellable: AnyCancellable?
    private var nodeJSStarted = false

    init() {
        setupNetworkRestoredAutoRetry()
    }

    func loadConfig(url: String) async {
        await loadConfig(vodUrl: url, liveUrl: nil)
    }

    func loadConfig(vodUrl: String, liveUrl: String?) async {
        let trimmedVod = vodUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLive = (liveUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVod.isEmpty else { return }
        let resolvedLive = trimmedLive.isEmpty ? trimmedVod : trimmedLive

        lastVodUrl = trimmedVod
        lastLiveUrl = resolvedLive
        configLoadError = nil

        do {
            try await ApiConfig.shared.loadConfigs(vodApiUrl: trimmedVod, liveApiUrl: resolvedLive)
            applyLoadedConfigState()
            await ensureNodeJSAndLoadSource()
        } catch {
            if !(error is CancellationError) {
                configLoadError = error.localizedDescription
            }
        }
    }

    func applyLoadedConfigState() {
        isConfigLoaded = true
        configLoadError = nil
        currentSourceKey = ApiConfig.shared.homeSourceBean?.key ?? ""
    }

    private func ensureNodeJSAndLoadSource() async {
        let hasSpiderSource = ApiConfig.shared.sourceBeanList.contains(where: { $0.isSpiderSource })
        guard hasSpiderSource else { return }

        if !nodeJSStarted {
            let success = await NodeJSManager.shared().startNodeJS()
            if success {
                nodeJSStarted = true
                await loadSpiderSource()
            } else {
                print("[AppState] Node.js 启动失败")
            }
        } else {
            await loadSpiderSource()
        }
    }

    private func loadSpiderSource() async {
        guard let spiderSource = ApiConfig.shared.sourceBeanList.first(where: { $0.isSpiderSource }) else { return }
        guard !spiderSource.api.isEmpty else { return }

        NodeJSManager.shared().loadSource(fromURL: spiderSource.api) { success, message in
            if success {
                print("[AppState] Spider 源加载成功")
            } else {
                print("[AppState] Spider 源加载失败: \(message ?? "未知错误")")
            }
        }
    }

    private func setupNetworkRestoredAutoRetry() {
        networkRestoredCancellable = NetworkMonitor.shared.networkRestoredPublisher
            .sink { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self, !self.isConfigLoaded, !self.lastVodUrl.isEmpty else { return }
                    self.isRetryingConfig = true
                    await self.loadConfig(vodUrl: self.lastVodUrl, liveUrl: self.lastLiveUrl)
                    self.isRetryingConfig = false
                }
            }
    }

    #if os(macOS)
    func enterPlayerFullScreen() {
        if splitViewVisibilityBeforePlayerFullScreen == nil {
            splitViewVisibilityBeforePlayerFullScreen = splitViewVisibility
        }
        splitViewVisibility = .detailOnly
    }

    func exitPlayerFullScreen() {
        guard let previous = splitViewVisibilityBeforePlayerFullScreen else { return }
        splitViewVisibility = previous
        splitViewVisibilityBeforePlayerFullScreen = nil
    }
    #endif
}
