import SwiftUI
import AVKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PlatformVideoPlayer: View {
    let player: AVPlayer

    var body: some View {
        #if os(macOS)
        MacOSPlayerView(player: player)
        #else
        IOSPlayerView(player: player)
        #endif
    }
}

#if os(macOS)
private struct MacOSPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player = nil
    }
}
#else
private struct IOSPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player = nil
    }
}
#endif

@MainActor
final class SystemPlayerSessionController: ObservableObject {
    fileprivate var player: AVPlayer?
    fileprivate var mediaURLString: String?
    fileprivate var resourceLoaderDelegate: CustomHeaderResourceLoaderDelegate?

    func setPlayer(_ newPlayer: AVPlayer, urlString: String, resourceLoaderDelegate: CustomHeaderResourceLoaderDelegate? = nil) {
        if player !== newPlayer {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
        player = newPlayer
        mediaURLString = urlString
        self.resourceLoaderDelegate = resourceLoaderDelegate
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        mediaURLString = nil
        resourceLoaderDelegate = nil
    }
}

struct PlayerView: View {
    let urlString: String
    var startPosition: Double = 0
    var onProgressChanged: ((Double, Double?) -> Void)? = nil
    var onPlaybackEnded: (() -> Void)? = nil
    var onToggleFullScreen: (() -> Void)? = nil
    var canPlayNext: Bool = false
    var onPlayNext: (() -> Void)? = nil
    var systemController: SystemPlayerSessionController? = nil
    var vlcController: VLCPlayerController? = nil
    var isFullScreenMode: Bool = false
    var httpHeaders: [String: String] = [:]
    @State private var fallbackToVLC = false
    @AppStorage(HawkConfig.PLAY_TYPE_VOD) private var vodPlayTypeRaw = -1
    @AppStorage(HawkConfig.PLAY_TYPE) private var legacyPlayTypeRaw = PlayerEngine.system.rawValue

    private var selectedEngine: PlayerEngine {
        let defaults = UserDefaults.standard
        let rawValue: Int
        if defaults.object(forKey: HawkConfig.PLAY_TYPE_VOD) != nil {
            rawValue = vodPlayTypeRaw
        } else if defaults.object(forKey: HawkConfig.PLAY_TYPE) != nil {
            rawValue = legacyPlayTypeRaw
        } else {
            rawValue = PlayerEngine.system.rawValue
        }
        return PlayerEngine.fromStoredValue(rawValue)
    }

    private var effectiveEngine: PlayerEngine {
        if fallbackToVLC, PlayerEngine.isVLCAvailable {
            return .vlc
        }
        return selectedEngine
    }

    var body: some View {
        Group {
            switch effectiveEngine {
            case .system:
                AVPlayerContentView(
                    urlString: urlString,
                    startPosition: startPosition,
                    httpHeaders: httpHeaders,
                    onProgressChanged: onProgressChanged,
                    onPlaybackEnded: onPlaybackEnded,
                    onToggleFullScreen: onToggleFullScreen,
                    canPlayNext: canPlayNext,
                    onPlayNext: onPlayNext,
                    sharedController: systemController,
                    onPlaybackFailed: {
                        if !httpHeaders.isEmpty, PlayerEngine.isVLCAvailable {
                            fallbackToVLC = true
                        }
                    }
                )
            case .vlc:
                VLCVodPlayerView(
                    urlString: urlString,
                    startPosition: startPosition,
                    httpHeaders: httpHeaders,
                    onProgressChanged: onProgressChanged,
                    onPlaybackEnded: onPlaybackEnded,
                    onToggleFullScreen: onToggleFullScreen,
                    canPlayNext: canPlayNext,
                    onPlayNext: onPlayNext,
                    sharedController: vlcController,
                    isFullScreenMode: isFullScreenMode
                )
            }
        }
        .id(selectedEngine.rawValue)
        .onAppear {
            if selectedEngine != .system {
                systemController?.stop()
            }
            if selectedEngine != .vlc {
                vlcController?.stop()
            }
        }
        .onChange(of: urlString) { _ in
            fallbackToVLC = false
        }
        .onChange(of: selectedEngine) { newValue in
            if newValue != .system {
                systemController?.stop()
            }
            if newValue != .vlc {
                vlcController?.stop()
            }
        }
    }
}

final class CustomHeaderResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
    private let originalScheme: String
    private let httpHeaders: [String: String]
    private var session: URLSession!
    private let lock = NSLock()
    private var _taskToRequest: [Int: AVAssetResourceLoadingRequest] = [:]
    private var _requestToTask: [ObjectIdentifier: URLSessionDataTask] = [:]

    static let customScheme = "tvboxstream"

    init(originalScheme: String, httpHeaders: [String: String]) {
        self.originalScheme = originalScheme
        self.httpHeaders = httpHeaders
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    static func makeCustomSchemeURL(from originalURL: URL) -> URL? {
        var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
        components?.scheme = customScheme
        return components?.url
    }

    private func restoreOriginalURL(from customURL: URL) -> URL? {
        var components = URLComponents(url: customURL, resolvingAgainstBaseURL: false)
        components?.scheme = originalScheme
        return components?.url
    }

    private func storeTask(_ task: URLSessionDataTask, for request: AVAssetResourceLoadingRequest) {
        lock.lock()
        _taskToRequest[task.taskIdentifier] = request
        _requestToTask[ObjectIdentifier(request)] = task
        lock.unlock()
    }

    private func requestForTask(_ task: URLSessionDataTask) -> AVAssetResourceLoadingRequest? {
        lock.lock()
        let request = _taskToRequest[task.taskIdentifier]
        lock.unlock()
        return request
    }

    private func taskForRequest(_ request: AVAssetResourceLoadingRequest) -> URLSessionDataTask? {
        lock.lock()
        let task = _requestToTask[ObjectIdentifier(request)]
        lock.unlock()
        return task
    }

    private func removeTask(_ task: URLSessionDataTask) {
        lock.lock()
        if let request = _taskToRequest[task.taskIdentifier] {
            _requestToTask.removeValue(forKey: ObjectIdentifier(request))
        }
        _taskToRequest.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
    }

    private func removeRequest(_ request: AVAssetResourceLoadingRequest) {
        lock.lock()
        if let task = _requestToTask[ObjectIdentifier(request)] {
            _taskToRequest.removeValue(forKey: task.taskIdentifier)
        }
        _requestToTask.removeValue(forKey: ObjectIdentifier(request))
        lock.unlock()
    }

    private func applyCustomHeaders(to request: inout URLRequest) {
        for (key, value) in httpHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let customURL = loadingRequest.request.url,
              let realURL = restoreOriginalURL(from: customURL) else {
            loadingRequest.finishLoading(with: NSError(domain: "CustomHeaderResourceLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法还原真实URL"]))
            return false
        }

        if loadingRequest.contentInformationRequest != nil && loadingRequest.dataRequest == nil {
            var headRequest = URLRequest(url: realURL)
            headRequest.httpMethod = "HEAD"
            applyCustomHeaders(to: &headRequest)
            let task = session.dataTask(with: headRequest)
            storeTask(task, for: loadingRequest)
            task.resume()
            return true
        }

        var request = URLRequest(url: realURL)
        applyCustomHeaders(to: &request)

        if let dataRequest = loadingRequest.dataRequest {
            let offset = dataRequest.requestedOffset
            let length = Int64(dataRequest.requestedLength)
            if dataRequest.requestsAllDataToEndOfResource {
                if offset > 0 {
                    request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
                }
            } else {
                request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
            }
        }

        let task = session.dataTask(with: request)
        storeTask(task, for: loadingRequest)
        task.resume()

        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        if let task = taskForRequest(loadingRequest) {
            task.cancel()
            removeRequest(loadingRequest)
        }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        guard let customURL = renewalRequest.request.url,
              let realURL = restoreOriginalURL(from: customURL) else {
            renewalRequest.finishLoading(with: NSError(domain: "CustomHeaderResourceLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法还原真实URL"]))
            return false
        }

        var request = URLRequest(url: realURL)
        applyCustomHeaders(to: &request)

        let task = session.dataTask(with: request)
        storeTask(task, for: renewalRequest)
        task.resume()

        return true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var newRequest = request
        applyCustomHeaders(to: &newRequest)
        completionHandler(newRequest)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let loadingRequest = requestForTask(dataTask) else {
            completionHandler(.cancel)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"
            ])
            loadingRequest.finishLoading(with: error)
            removeTask(dataTask)
            completionHandler(.cancel)
            return
        }

        if let contentRequest = loadingRequest.contentInformationRequest {
            contentRequest.isByteRangeAccessSupported = true

            if httpResponse.statusCode == 206,
               let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
                let parts = contentRange.split(separator: "/")
                if let totalStr = parts.last, let total = Int64(totalStr) {
                    contentRequest.contentLength = total
                }
            } else if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
                      let length = Int64(contentLength) {
                contentRequest.contentLength = length
            }

            if let contentType = httpResponse.mimeType {
                contentRequest.contentType = contentType
            }
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let loadingRequest = requestForTask(dataTask) else { return }
        loadingRequest.dataRequest?.respond(with: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let dataTask = task as? URLSessionDataTask else { return }
        guard let loadingRequest = requestForTask(dataTask) else { return }
        removeTask(dataTask)

        if let error = error {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                return
            }
            loadingRequest.finishLoading(with: error)
        } else {
            loadingRequest.finishLoading()
        }
    }
}

struct AVPlayerContentView: View {
    private static let supportedPlaybackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    let urlString: String
    var startPosition: Double = 0
    var httpHeaders: [String: String] = [:]
    var onProgressChanged: ((Double, Double?) -> Void)? = nil
    var onPlaybackEnded: (() -> Void)? = nil
    var onToggleFullScreen: (() -> Void)? = nil
    var canPlayNext: Bool = false
    var onPlayNext: (() -> Void)? = nil
    var sharedController: SystemPlayerSessionController? = nil
    var onPlaybackFailed: (() -> Void)? = nil
    @AppStorage(HawkConfig.PLAY_SPEED) private var savedPlaybackRate = 1.0
    @State private var player: AVPlayer?
    @State private var playbackEndObserver: NSObjectProtocol?
    @State private var timeObserverToken: Any?
    @State private var retainedResourceLoaderDelegate: CustomHeaderResourceLoaderDelegate?

    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var volume: Double = 1.0
    @State private var rate: Float = 1.0
    @State private var isPreparing = true
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var isDraggingProgress = false
    @State private var draggingSeconds: Double = 0
    @State private var playerObservers: [NSKeyValueObservation] = []

    var body: some View {
        ZStack {
            Group {
                if let player = player {
                    PlatformVideoPlayer(player: player)
                } else {
                    ZStack {
                        Color.black
                        ProgressView()
                            .tint(.white)
                    }
                }
            }

            if isPreparing {
                ProgressView()
                    .tint(.white)
            }

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControls()
                }
        }
        .overlay {
            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .overlay {
            SystemPlayerKeyboardCaptureView(
                onLeft: { seek(by: -seekStep) },
                onRight: { seek(by: seekStep) },
                onTogglePlayPause: { togglePlayPause() },
                onToggleFullScreen: { onToggleFullScreen?() },
                onVolumeDown: { wakeUpControls(); adjustVolume(by: -volumeStep) },
                onVolumeUp: { wakeUpControls(); adjustVolume(by: volumeStep) }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
        }
        #if os(macOS)
        .onContinuousHover { phase in
            switch phase {
            case .active(_): wakeUpControls()
            case .ended: break
            }
        }
        #endif
        .onAppear {
            syncRateFromSettings()
            setupPlayer()
            wakeUpControls()
        }
        .onChange(of: urlString) { _ in
            syncRateFromSettings()
            setupPlayer()
            wakeUpControls()
        }
        .onDisappear {
            cleanupPlayer(keepSharedPlayer: sharedController != nil)
            controlsTimer?.invalidate()
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(currentTime.durationString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 50, alignment: .leading)

                    Slider(
                        value: Binding(
                            get: { isDraggingProgress ? draggingSeconds : currentTime },
                            set: {
                                draggingSeconds = $0
                                wakeUpControls()
                            }
                        ),
                        in: 0...progressUpperBound,
                        onEditingChanged: { editing in
                            isDraggingProgress = editing
                            wakeUpControls()
                            if !editing {
                                seek(to: draggingSeconds)
                            }
                        }
                    )
                    .tint(.white)

                    Text(duration.durationString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 50, alignment: .trailing)
                }
                .padding(.horizontal, 16)

                HStack(spacing: 0) {
                    HStack(spacing: 16) {
                        playbackRateMenu
                    }

                    Spacer()

                    HStack(spacing: 28) {
                        Button {
                            wakeUpControls()
                            seek(by: -seekStep)
                        } label: {
                            Image(systemName: "gobackward.\(Int(seekStep))")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)

                        Button {
                            togglePlayPause()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28, weight: .medium))
                        }
                        .buttonStyle(.plain)

                        Button {
                            wakeUpControls()
                            seek(by: seekStep)
                        } label: {
                            Image(systemName: "goforward.\(Int(seekStep))")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)

                        if canPlayNext {
                            Button {
                                wakeUpControls()
                                onPlayNext?()
                            } label: {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 20))
                            }
                            .buttonStyle(.plain)
                            .opacity(canPlayNext ? 1 : 0.4)
                        }
                    }

                    Spacer()

                    HStack(spacing: 16) {
                        Button {
                            wakeUpControls()
                            let newVolume = volume > 0 ? 0.0 : 1.0
                            player?.volume = Float(newVolume)
                        } label: {
                            Image(systemName: volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)

                        Button {
                            wakeUpControls()
                            onToggleFullScreen?()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .animation(.easeInOut(duration: 0.25), value: showControls)
    }

    private var playbackRateMenu: some View {
        Menu {
            ForEach(Self.supportedPlaybackRates, id: \.self) { r in
                Button {
                    wakeUpControls()
                    setPlaybackRate(r)
                } label: {
                    HStack {
                        Text("\(String(format: "%.1f", r))x")
                        if r == rate {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(String(format: "%.1f", rate))x")
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func setupPlayer() {
        guard let url = URL(string: urlString) else { return }
        let targetURLString = url.absoluteString
        let preferredRate = normalizedSavedPlaybackRate
        rate = preferredRate

        if let sharedController,
           sharedController.mediaURLString == targetURLString,
           let sharedPlayer = sharedController.player {
            cleanupPlayer(keepSharedPlayer: true)
            player = sharedPlayer
            applyPreferredPlaybackRate(to: sharedPlayer)
            bindPlayerObservers(for: sharedPlayer)
            reportProgress(for: sharedPlayer)
            return
        }

        cleanupPlayer()

        let playerItem: AVPlayerItem
        var delegate: CustomHeaderResourceLoaderDelegate?

        if !httpHeaders.isEmpty,
           let customSchemeURL = CustomHeaderResourceLoaderDelegate.makeCustomSchemeURL(from: url) {
            let resourceLoaderDelegate = CustomHeaderResourceLoaderDelegate(
                originalScheme: url.scheme ?? "https",
                httpHeaders: httpHeaders
            )
            let asset = AVURLAsset(url: customSchemeURL)
            asset.resourceLoader.setDelegate(
                resourceLoaderDelegate,
                queue: DispatchQueue(label: "com.tvbox.resourceloader")
            )
            playerItem = AVPlayerItem(asset: asset)
            delegate = resourceLoaderDelegate
        } else {
            playerItem = AVPlayerItem(url: url)
        }

        let newPlayer = AVPlayer(playerItem: playerItem)
        if #available(iOS 17.0, *) {
            newPlayer.defaultRate = preferredRate
        }
        retainedResourceLoaderDelegate = delegate
        if let sharedController {
            sharedController.setPlayer(newPlayer, urlString: targetURLString, resourceLoaderDelegate: delegate)
        }

        player = newPlayer
        bindPlayerObservers(for: newPlayer)
        startPlayback(for: newPlayer)
    }

    private func bindPlayerObservers(for player: AVPlayer) {
        var observers = [
            player.observe(\.timeControlStatus, options: [.new]) { p, _ in
                DispatchQueue.main.async { isPlaying = p.timeControlStatus == .playing }
            },
            player.observe(\.reasonForWaitingToPlay, options: [.new]) { p, _ in
                DispatchQueue.main.async { isPreparing = p.reasonForWaitingToPlay != nil }
            },
            player.observe(\.volume, options: [.new]) { p, _ in
                DispatchQueue.main.async { volume = Double(p.volume) }
            },
            player.observe(\.rate, options: [.new]) { p, _ in
                let currentRate = p.rate
                guard currentRate > 0 else { return }
                let normalized = Self.normalizedPlaybackRate(from: currentRate)
                DispatchQueue.main.async {
                    rate = normalized
                    if abs(savedPlaybackRate - Double(normalized)) > 0.001 {
                        savedPlaybackRate = Double(normalized)
                    }
                }
            }
        ]

        if let item = player.currentItem {
            observers.append(item.observe(\.status, options: [.new]) { [self] item, _ in
                if item.status == .failed {
                    DispatchQueue.main.async {
                        onPlaybackFailed?()
                    }
                }
            })
        }

        playerObservers = observers
        observePlaybackProgress(for: player)
        observePlaybackEnd(for: player)
        isPlaying = player.timeControlStatus == .playing
        isPreparing = player.reasonForWaitingToPlay != nil
        volume = Double(player.volume)
        rate = normalizedSavedPlaybackRate
    }

    private func detachPlayerObservers() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let observer = playbackEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackEndObserver = nil
        }
        playerObservers.forEach { $0.invalidate() }
        playerObservers.removeAll()
    }

    private func cleanupPlayer(keepSharedPlayer: Bool = false) {
        let currentPlayer = player
        detachPlayerObservers()

        guard let currentPlayer else { return }
        if keepSharedPlayer, sharedController?.player === currentPlayer {
            player = nil
            return
        }

        currentPlayer.pause()
        currentPlayer.replaceCurrentItem(with: nil)
        if sharedController?.player === currentPlayer {
            sharedController?.player = nil
            sharedController?.mediaURLString = nil
            sharedController?.resourceLoaderDelegate = nil
        }
        retainedResourceLoaderDelegate = nil
        player = nil
    }

    private func startPlayback(for player: AVPlayer) {
        let target = max(startPosition, 0)

        if target > 0 {
            let seekTime = CMTime(seconds: target, preferredTimescale: 600)
            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                reportProgress(for: player)
                playAtPreferredRate(player)
            }
        } else {
            playAtPreferredRate(player)
        }
    }

    private func togglePlayPause() {
        guard let player = player else { return }
        if player.rate == 0 {
            playAtPreferredRate(player)
        } else {
            player.pause()
        }
        wakeUpControls()
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showControls.toggle()
        }
        if showControls {
            wakeUpControls()
        } else {
            controlsTimer?.invalidate()
        }
    }

    private func wakeUpControls() {
        withAnimation(.easeInOut(duration: 0.25)) { showControls = true }
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                showControls = false
            }
        }
    }

    private func observePlaybackEnd(for player: AVPlayer) {
        guard let item = player.currentItem else { return }

        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            onPlaybackEnded?()
        }
    }

    private func observePlaybackProgress(for player: AVPlayer) {
        let interval = CMTime(seconds: 1, preferredTimescale: 2)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
            reportProgress(for: player)
        }
    }

    private func reportProgress(for player: AVPlayer?) {
        guard let player else { return }
        let current = player.currentTime().seconds
        guard current.isFinite, current >= 0 else { return }

        if !isDraggingProgress {
            self.currentTime = current
            self.draggingSeconds = current
        }

        let rawDuration = player.currentItem?.duration.seconds
        if let rawDuration, rawDuration.isFinite, rawDuration >= 0 {
            self.duration = rawDuration
        }
        onProgressChanged?(current, duration > 0 ? duration : nil)
    }

    private var seekStep: Double {
        let saved = UserDefaults.standard.integer(forKey: HawkConfig.PLAY_TIME_STEP)
        return Double(saved > 0 ? saved : 10)
    }

    private var volumeStep: Double { 0.1 }

    private var progressUpperBound: Double {
        max(duration, max(currentTime, 1))
    }

    private var normalizedSavedPlaybackRate: Float {
        Self.normalizedPlaybackRate(from: Float(savedPlaybackRate))
    }

    private static func normalizedPlaybackRate(from raw: Float) -> Float {
        guard !supportedPlaybackRates.isEmpty else { return 1.0 }
        return supportedPlaybackRates.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? 1.0
    }

    private func syncRateFromSettings() {
        rate = normalizedSavedPlaybackRate
    }

    private func setPlaybackRate(_ value: Float) {
        let normalized = Self.normalizedPlaybackRate(from: value)
        rate = normalized
        savedPlaybackRate = Double(normalized)
        guard let player else { return }
        if #available(iOS 17.0, *) {
            player.defaultRate = normalized
        }
        if player.rate > 0 {
            player.rate = normalized
        }
    }

    private func applyPreferredPlaybackRate(to player: AVPlayer) {
        let normalized = normalizedSavedPlaybackRate
        rate = normalized
        if #available(iOS 17.0, *) {
            player.defaultRate = normalized
        }
        if player.rate > 0 {
            player.rate = normalized
        }
    }

    private func playAtPreferredRate(_ player: AVPlayer) {
        let normalized = normalizedSavedPlaybackRate
        rate = normalized
        if #available(iOS 17.0, *) {
            player.defaultRate = normalized
        }
        player.playImmediately(atRate: normalized)
    }

    private func seek(to seconds: Double) {
        guard let player = player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func seek(by offset: Double) {
        guard let player else { return }

        let current = player.currentTime().seconds
        guard current.isFinite else { return }
        let wasPlaying = player.rate != 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate

        var target = max(current + offset, 0)
        if let duration = player.currentItem?.duration.seconds, duration.isFinite {
            target = min(target, duration)
        }

        player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { _ in
            reportProgress(for: player)
            if wasPlaying {
                playAtPreferredRate(player)
            }
        }
    }

    private func adjustVolume(by delta: Double) {
        guard let player else { return }
        let current = Double(player.volume)
        let target = min(max(current + delta, 0), 1)
        player.volume = Float(target)
    }
}

#if os(macOS)
private struct SystemPlayerKeyboardCaptureView: NSViewRepresentable {
    let onLeft: () -> Void
    let onRight: () -> Void
    let onTogglePlayPause: () -> Void
    let onToggleFullScreen: () -> Void
    let onVolumeDown: () -> Void
    let onVolumeUp: () -> Void

    func makeNSView(context: Context) -> SystemPlayerKeyCaptureNSView {
        let view = SystemPlayerKeyCaptureNSView(frame: .zero)
        applyCallbacks(to: view)
        DispatchQueue.main.async { view.activate() }
        return view
    }

    func updateNSView(_ nsView: SystemPlayerKeyCaptureNSView, context: Context) {
        applyCallbacks(to: nsView)
        DispatchQueue.main.async { nsView.activate() }
    }

    private func applyCallbacks(to view: SystemPlayerKeyCaptureNSView) {
        view.onLeft = onLeft
        view.onRight = onRight
        view.onTogglePlayPause = onTogglePlayPause
        view.onToggleFullScreen = onToggleFullScreen
        view.onVolumeDown = onVolumeDown
        view.onVolumeUp = onVolumeUp
    }
}

private final class SystemPlayerKeyCaptureNSView: NSView {
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?
    var onVolumeDown: (() -> Void)?
    var onVolumeUp: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activate()
    }

    func activate() { window?.makeFirstResponder(self) }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123: onLeft?(); return
        case 124: onRight?(); return
        case 125: onVolumeDown?(); return
        case 126: onVolumeUp?(); return
        case 49: onTogglePlayPause?(); return
        default: break
        }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch key {
        case "k": onTogglePlayPause?()
        case "f": onToggleFullScreen?()
        default: super.keyDown(with: event)
        }
    }
}
#else
private struct SystemPlayerKeyboardCaptureView: UIViewRepresentable {
    let onLeft: () -> Void
    let onRight: () -> Void
    let onTogglePlayPause: () -> Void
    let onToggleFullScreen: () -> Void
    let onVolumeDown: () -> Void
    let onVolumeUp: () -> Void

    func makeUIView(context: Context) -> SystemPlayerKeyCaptureUIView {
        let view = SystemPlayerKeyCaptureUIView(frame: .zero)
        applyCallbacks(to: view)
        DispatchQueue.main.async { view.activate() }
        return view
    }

    func updateUIView(_ uiView: SystemPlayerKeyCaptureUIView, context: Context) {
        applyCallbacks(to: uiView)
        DispatchQueue.main.async { uiView.activate() }
    }

    private func applyCallbacks(to view: SystemPlayerKeyCaptureUIView) {
        view.onLeft = onLeft
        view.onRight = onRight
        view.onTogglePlayPause = onTogglePlayPause
        view.onToggleFullScreen = onToggleFullScreen
        view.onVolumeDown = onVolumeDown
        view.onVolumeUp = onVolumeUp
    }
}

private final class SystemPlayerKeyCaptureUIView: UIView {
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?
    var onVolumeDown: (() -> Void)?
    var onVolumeUp: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(handleLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleRight)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleVolumeDown)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleVolumeUp)),
            UIKeyCommand(input: " ", modifierFlags: [], action: #selector(handleTogglePlayPause)),
            UIKeyCommand(input: "k", modifierFlags: [], action: #selector(handleTogglePlayPause)),
            UIKeyCommand(input: "f", modifierFlags: [], action: #selector(handleToggleFullScreen))
        ]
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        activate()
    }

    func activate() { becomeFirstResponder() }

    @objc private func handleLeft() { onLeft?() }
    @objc private func handleRight() { onRight?() }
    @objc private func handleVolumeDown() { onVolumeDown?() }
    @objc private func handleVolumeUp() { onVolumeUp?() }
    @objc private func handleTogglePlayPause() { onTogglePlayPause?() }
    @objc private func handleToggleFullScreen() { onToggleFullScreen?() }
}
#endif
