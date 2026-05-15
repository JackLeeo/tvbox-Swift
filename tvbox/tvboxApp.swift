import SwiftUI
import Combine

@main
struct tvboxApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(networkMonitor)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        Task { await appState.handleSceneActive() }
                    }
                }
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
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupNetworkRestoredAutoRetry()
        ApiConfig.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
            await ensureNodeJSAndLoadSource()
            applyLoadedConfigState()
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

        let loadSuccess = await withCheckedContinuation { continuation in
            NodeJSManager.shared().loadSource(fromURL: spiderSource.api) { success, message in
                if success {
                    print("[AppState] Spider 源加载成功")
                } else {
                    print("[AppState] Spider 源加载失败: \(message ?? "未知错误")")
                }
                continuation.resume(returning: success)
            }
        }

        guard loadSuccess else { return }

        let portReady = await withCheckedContinuation { continuation in
            NodeJSManager.shared().waitForSpiderPort { ready in
                continuation.resume(returning: ready)
            }
        }

        guard portReady else {
            print("[AppState] 等待 spiderPort 超时")
            return
        }

        await fetchSpiderConfig()
    }

    private func fetchSpiderConfig() async {
        let spiderPort = NodeJSManager.shared().getSpiderPort()
        guard spiderPort > 0 else {
            print("[AppState] spiderPort 为 0，无法获取线路配置")
            return
        }

        do {
            let config = try await SpiderService.shared.getCatConfig()
            ApiConfig.shared.updateSourceBeansFromSpiderConfig(config, spiderUrl: "")

            if let firstSource = ApiConfig.shared.sourceBeanList.first {
                SpiderService.shared.setCurrentSpider(
                    key: firstSource.key,
                    type: firstSource.type,
                    apiBase: firstSource.api
                )
                try? await SpiderService.shared.initSpider()
            }
        } catch {
            print("[AppState] 获取 Spider 配置失败: \(error)")
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

    func handleSceneActive() async {
        guard isConfigLoaded else { return }
        let hasSpiderSource = ApiConfig.shared.sourceBeanList.contains(where: { $0.isSpiderSource })
        guard hasSpiderSource else { return }

        let spiderPort = NodeJSManager.shared().getSpiderPort()
        if spiderPort <= 0 || !NodeJSManager.shared().isRunning {
            nodeJSStarted = false
            await ensureNodeJSAndLoadSource()
        } else {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(spiderPort)/config")!)
            request.httpMethod = "GET"
            request.timeoutInterval = 5
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    nodeJSStarted = false
                    await ensureNodeJSAndLoadSource()
                }
            } catch {
                nodeJSStarted = false
                await ensureNodeJSAndLoadSource()
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
