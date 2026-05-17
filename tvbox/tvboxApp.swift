import SwiftUI
import Combine
#if os(iOS)
import AVFoundation
#endif

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AVAudioSession setup failed: \(error)")
        }
        return true
    }
}
#endif

enum LoadingPhase: Equatable {
    case idle
    case loadingConfig
    case startingNodeJS
    case downloadingSource
    case verifyingMD5
    case loadingSource
    case waitingSpiderPort
    case fetchingSpiderConfig
    case initializingSpider
    case reconnecting
    case completed
    case failed(String)

    var displayText: String {
        switch self {
        case .idle: return ""
        case .loadingConfig: return "正在加载配置..."
        case .startingNodeJS: return "正在启动 Node.js 运行时..."
        case .downloadingSource: return "正在下载源文件..."
        case .verifyingMD5: return "正在校验文件完整性..."
        case .loadingSource: return "正在加载 Spider 源..."
        case .waitingSpiderPort: return "等待 Spider 服务就绪..."
        case .fetchingSpiderConfig: return "正在获取线路配置..."
        case .initializingSpider: return "正在初始化 Spider..."
        case .reconnecting: return "正在重连服务..."
        case .completed: return "加载完成"
        case .failed(let msg): return "加载失败: \(msg)"
        }
    }

    var isLoading: Bool {
        switch self {
        case .idle, .completed, .failed: return false
        default: return true
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

extension Notification.Name {
    static let spiderServiceDidReconnect = Notification.Name("spiderServiceDidReconnect")
}

@main
struct tvboxApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
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
    @Published var pendingSearchKeyword: String?
    @Published var loadingPhase: LoadingPhase = .idle

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
        loadingPhase = .loadingConfig

        do {
            try await ApiConfig.shared.loadConfigs(vodApiUrl: trimmedVod, liveApiUrl: resolvedLive)
            await ensureNodeJSAndLoadSource()
            loadingPhase = .completed
            applyLoadedConfigState()
        } catch {
            if !(error is CancellationError) {
                configLoadError = error.localizedDescription
                loadingPhase = .failed(error.localizedDescription)
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
            loadingPhase = .startingNodeJS
            let success = await NodeJSManager.shared().startNodeJS()
            if success {
                nodeJSStarted = true
                await loadSpiderSource()
            } else {
                loadingPhase = .failed("Node.js 启动失败")
                print("[AppState] Node.js 启动失败")
            }
        } else {
            await loadSpiderSource()
        }
    }

    private func loadSpiderSource() async {
        guard let spiderSource = ApiConfig.shared.sourceBeanList.first(where: { $0.isSpiderSource }) else { return }
        guard !spiderSource.api.isEmpty else { return }

        loadingPhase = .downloadingSource
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

        guard loadSuccess else {
            loadingPhase = .failed("Spider 源加载失败")
            return
        }

        loadingPhase = .waitingSpiderPort
        let portReady = await withCheckedContinuation { continuation in
            NodeJSManager.shared().waitForSpiderPort { ready in
                continuation.resume(returning: ready)
            }
        }

        guard portReady else {
            loadingPhase = .failed("等待 Spider 服务超时")
            print("[AppState] 等待 spiderPort 超时")
            return
        }

        await fetchSpiderConfig()
    }

    private func fetchSpiderConfig() async {
        let spiderPort = NodeJSManager.shared().getSpiderPort()
        guard spiderPort > 0 else {
            loadingPhase = .failed("Spider 端口为 0")
            print("[AppState] spiderPort 为 0，无法获取线路配置")
            return
        }

        loadingPhase = .fetchingSpiderConfig
        do {
            let config = try await SpiderService.shared.getCatConfig()
            ApiConfig.shared.updateSourceBeansFromSpiderConfig(config, spiderUrl: "")

            if let firstSource = ApiConfig.shared.sourceBeanList.first {
                loadingPhase = .initializingSpider
                SpiderService.shared.setCurrentSpider(
                    key: firstSource.key,
                    type: firstSource.type,
                    apiBase: firstSource.api
                )
                try? await SpiderService.shared.initSpider()
            }
        } catch {
            loadingPhase = .failed("获取线路配置失败")
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
        let needsRestart: Bool

        if spiderPort <= 0 || !NodeJSManager.shared().isRunning {
            needsRestart = true
        } else {
            needsRestart = !(await checkSpiderHealth(spiderPort: spiderPort))
        }

        guard needsRestart else { return }

        loadingPhase = .reconnecting
        SpiderService.shared.invalidateSession()
        NetworkManager.shared.invalidateSession()

        nodeJSStarted = false
        await ensureNodeJSAndLoadSource()

        if nodeJSStarted {
            loadingPhase = .completed
            NotificationCenter.default.post(name: .spiderServiceDidReconnect, object: nil)
        } else {
            loadingPhase = .failed("服务重连失败")
        }
    }

    private func checkSpiderHealth(spiderPort: Int) async -> Bool {
        for attempt in 0..<3 {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(spiderPort)/config")!)
            request.httpMethod = "GET"
            request.timeoutInterval = attempt == 0 ? 3 : 5
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    return true
                }
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64((attempt + 1) * 1_000_000_000))
                }
            }
        }
        return false
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
