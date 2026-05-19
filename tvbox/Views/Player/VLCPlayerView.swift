import SwiftUI
import Darwin

#if canImport(VLCKitSPM)
import VLCKitSPM
#if os(iOS)
import UIKit
#endif

@MainActor
final class VLCPlayerController: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    static let supportedPlaybackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    private static let defaultVolume = 100
    private static let maxVolume = 200
    private static let drawableSizeChangeThreshold: CGFloat = 24
    private static let drawableRebindMinimumInterval: TimeInterval = 1.2
    // 这些选项在播放器实例级别生效，优先约束 libvlc 的追时钟/丢帧行为。
    private static let stablePlaybackOptions: [String] = [
        "--no-drop-late-frames",
        "--no-skip-frames",
        "--clock-synchro=0",
        "--clock-jitter=0"
    ]
    private static let playerInstanceSelector = NSSelectorFromString("playerInstance")
    private static let libVLCStopAsync: LibVLCStopAsyncFunction? = {
        // RTLD_DEFAULT 在 Swift 中不可直接用常量名，-2 等价于 C 宏 RTLD_DEFAULT。
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        return "libvlc_media_player_stop_async".withCString { symbolName in
            guard let symbol = dlsym(defaultHandle, symbolName) else { return nil }
            return unsafeBitCast(symbol, to: LibVLCStopAsyncFunction.self)
        }
    }()
    private typealias LibVLCStopAsyncFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
    
    let mediaPlayer = VLCMediaPlayer(options: VLCPlayerController.stablePlaybackOptions)
    @Published var isPreparing = true
    @Published var isPlaying = false
    @Published var currentTimeSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var playbackRate: Float = 1.0
    @Published var volume: Int = defaultVolume
    #if os(macOS)
    private let persistentDrawableView = NSView(frame: .zero)
    private weak var lastAttachedContainer: NSView?
    #else
    private let persistentDrawableView = UIView(frame: .zero)
    private weak var lastAttachedContainer: UIView?
    #endif
    private var rebindWorkItems: [DispatchWorkItem] = []
    private var lastDrawableContainerIdentifier: ObjectIdentifier?
    private var lastDrawableContainerSize: CGSize = .zero
    private var lastDrawableRebindAt: Date = .distantPast
    #if os(iOS)
    private weak var preferredDrawableContainer: UIView?
    #endif
    
    var hasValidDuration: Bool {
        durationSeconds > 0
    }

    var videoWidth: Int {
        Int(mediaPlayer.videoSize.width)
    }

    var videoHeight: Int {
        Int(mediaPlayer.videoSize.height)
    }
    
    private var progressTimer: Timer?
    private var pendingSeekSeconds: Double?
    private var isLive = false
    private var isInBufferingState = false
    private var pendingVodBufferingConfirmWorkItem: DispatchWorkItem?
    private var bufferingBaselineSecondsVod: Double = 0
    private var decodeMode: VideoDecodeMode = .auto
    private var decodeModeOverride: VideoDecodeMode?
    private var hasAttemptedSoftDecodeFallback = false
    private var bufferMode: VLCBufferMode = .defaultMode
    private var bufferingFallbackWorkItem: DispatchWorkItem?
    private var delayedPreparingWorkItem: DispatchWorkItem?
    private var currentMediaURLString: String?
    private var currentMediaIsLive = false
    private var currentMediaDecodeMode: VideoDecodeMode = .auto
    private var currentMediaBufferMode: VLCBufferMode = .defaultMode
    private var onProgressChanged: ((Double, Double?) -> Void)?
    private var onPlaybackEnded: (() -> Void)?
    private var onPlaybackFailed: (() -> Void)?
    private let progressUpdateIntervalVod: TimeInterval = 0.5
    private let progressUpdateIntervalLive: TimeInterval = 1.0
    private let bufferingFallbackThresholdLive: TimeInterval = 4.0
    private let bufferingConfirmDelayVod: TimeInterval = 0.35
    private let bufferingIndicatorDelayVod: TimeInterval = 1.2
    private let vodBufferingProgressAdvanceThreshold: Double = 0.25
    private let progressPublishThreshold: Double = 0.25
    private let durationPublishThreshold: Double = 0.5
    private var lastNonZeroVolume = defaultVolume
    
    override init() {
        super.init()
        let savedObj = UserDefaults.standard.object(forKey: HawkConfig.PLAY_SPEED)
        let savedRate = savedObj != nil ? Float(UserDefaults.standard.double(forKey: HawkConfig.PLAY_SPEED)) : 1.0
        playbackRate = Self.normalizedPlaybackRate(from: savedRate)
        decodeMode = VideoDecodeMode.fromStoredValue(
            UserDefaults.standard.integer(forKey: HawkConfig.PLAY_DECODE_MODE)
        )
        bufferMode = VLCBufferMode.fromStoredValue(
            UserDefaults.standard.integer(forKey: HawkConfig.PLAY_VLC_BUFFER_MODE)
        )
        let savedVolumeObj = UserDefaults.standard.object(forKey: HawkConfig.PLAY_VOLUME)
        let savedVolume = savedVolumeObj != nil ? UserDefaults.standard.integer(forKey: HawkConfig.PLAY_VOLUME) : Self.defaultVolume
        volume = Self.normalizedVolume(from: savedVolume)
        if volume > 0 {
            lastNonZeroVolume = volume
        }
        #if os(macOS)
        persistentDrawableView.wantsLayer = true
        persistentDrawableView.layer?.backgroundColor = NSColor.black.cgColor
        #else
        persistentDrawableView.backgroundColor = .black
        #endif
        mediaPlayer.delegate = self
        mediaPlayer.drawable = persistentDrawableView
    }
    
    func play(
        url: URL,
        startPosition: Double,
        isLive: Bool,
        onProgressChanged: ((Double, Double?) -> Void)?,
        onPlaybackEnded: (() -> Void)?,
        onPlaybackFailed: (() -> Void)?,
        httpHeaders: [String: String] = [:]
    ) {
        let targetURLString = url.absoluteString
        let isNewMedia = currentMediaURLString != targetURLString || currentMediaIsLive != isLive
        if isNewMedia {
            resetPlaybackRecoveryState()
        }
        syncDecodeModeFromSettings()
        syncBufferModeFromSettings()
        
        // 同一路径/同场景（点播或直播）时复用当前实例，避免切全屏触发重新加载
        if currentMediaURLString == targetURLString,
           currentMediaIsLive == isLive,
           currentMediaDecodeMode == decodeMode,
           currentMediaBufferMode == bufferMode,
           mediaPlayer.media != nil {
            self.onProgressChanged = onProgressChanged
            self.onPlaybackEnded = onPlaybackEnded
            self.onPlaybackFailed = onPlaybackFailed
            self.isLive = isLive
            applyPlaybackRate()
            applyVolume()
            refreshPlaybackFlags()
            emitProgress()
            return
        }
        
        stopProgressTimer()
        cancelBufferingFallbackTimer()
        cancelDelayedPreparingIndicator()
        cancelPendingVodBufferingConfirmation()
        isInBufferingState = false
        self.onProgressChanged = onProgressChanged
        self.onPlaybackEnded = onPlaybackEnded
        self.onPlaybackFailed = onPlaybackFailed
        self.isLive = isLive
        pendingSeekSeconds = isLive ? nil : max(startPosition, 0)
        setPlaybackStatus(preparing: true, playing: false)
        resetProgressState()
        
        mediaPlayer.stop()
        let media = VLCMedia(url: url)
        
        let cacheConfig = Self.cacheConfig(isLive: isLive, bufferMode: bufferMode)
        let enableFrameDrop = isLive ? bufferMode.enableFrameDrop : false
        let enableSkipFrames = isLive && bufferMode.enableFrameDrop
        var mediaOptions: [String: Any] = [
            "network-caching": cacheConfig.network,
            "live-caching": cacheConfig.live,
            "file-caching": cacheConfig.file,
            "http-reconnect": 1
        ]
        if !isLive {
            mediaOptions["avcodec-hurry-up"] = 0
            mediaOptions["clock-synchro"] = 0
        }

        if let hwOption = decodeMode.vlcHardwareDecodeOption {
            mediaOptions["avcodec-hw"] = hwOption
        }
        if isLive {
            mediaOptions["avcodec-fast"] = 1
        }
        if url.scheme?.lowercased() == "rtsp" {
            mediaOptions["rtsp-tcp"] = 1
        }
        
        media.addOptions(mediaOptions)
        if !httpHeaders.isEmpty {
            if let cookie = httpHeaders["Cookie"] ?? httpHeaders["cookie"] {
                media.addOption(":http-cookie=\(cookie)")
            }
            if let referer = httpHeaders["Referer"] ?? httpHeaders["referer"] ?? httpHeaders["Referrer"] ?? httpHeaders["referrer"] {
                media.addOption(":http-referrer=\(referer)")
            }
            if let ua = httpHeaders["User-Agent"] ?? httpHeaders["user-agent"] ?? httpHeaders["UserAgent"] {
                media.addOption(":http-user-agent=\(ua)")
            }
        }
        // 对布尔型选项使用显式 no- 前缀，避免 0/1 在不同 libvlc 版本下解释不一致。
        media.addOption(enableFrameDrop ? "drop-late-frames" : "no-drop-late-frames")
        media.addOption(enableSkipFrames ? "skip-frames" : "no-skip-frames")
        
        mediaPlayer.media = media
        mediaPlayer.play()
        applyPlaybackRate()
        applyVolume()
        startProgressTimer()
        currentMediaURLString = targetURLString
        currentMediaIsLive = isLive
        currentMediaDecodeMode = decodeMode
        currentMediaBufferMode = bufferMode
    }
    
    func stop() {
        stopProgressTimer()
        resetPlaybackRecoveryState()
        cancelScheduledRebinds()
        stopMediaPlayer()
        mediaPlayer.media = nil
        onProgressChanged = nil
        onPlaybackEnded = nil
        onPlaybackFailed = nil
        pendingSeekSeconds = nil
        setPlaybackStatus(preparing: false, playing: false)
        resetProgressState()
        currentMediaURLString = nil
        currentMediaIsLive = false
        currentMediaDecodeMode = .auto
        currentMediaBufferMode = .defaultMode
    }
    
    func togglePlayback() {
        if isPlaying {
            mediaPlayer.pause()
        } else {
            mediaPlayer.play()
            applyPlaybackRate()
        }
    }
    
    func setPlaybackRate(_ rate: Float) {
        let normalized = Self.normalizedPlaybackRate(from: rate)
        playbackRate = normalized
        UserDefaults.standard.set(Double(normalized), forKey: HawkConfig.PLAY_SPEED)
        applyPlaybackRate()
    }
    
    func increasePlaybackRate() {
        guard let index = Self.supportedPlaybackRates.firstIndex(of: playbackRate),
              index + 1 < Self.supportedPlaybackRates.count else { return }
        setPlaybackRate(Self.supportedPlaybackRates[index + 1])
    }
    
    func decreasePlaybackRate() {
        guard let index = Self.supportedPlaybackRates.firstIndex(of: playbackRate),
              index - 1 >= 0 else { return }
        setPlaybackRate(Self.supportedPlaybackRates[index - 1])
    }

    func setVolume(_ value: Int) {
        let normalized = Self.normalizedVolume(from: value)
        if volume != normalized {
            volume = normalized
        }
        if normalized > 0 {
            lastNonZeroVolume = normalized
        }
        UserDefaults.standard.set(normalized, forKey: HawkConfig.PLAY_VOLUME)
        applyVolume()
    }

    func toggleMute() {
        if volume == 0 {
            let restored = lastNonZeroVolume > 0 ? lastNonZeroVolume : Self.defaultVolume
            setVolume(restored)
        } else {
            setVolume(0)
        }
    }
    
    #if os(macOS)
    func attachDrawable(to container: NSView) {
        let containerIdentifier = ObjectIdentifier(container)
        let containerSize = container.bounds.size
        let containerChanged = lastDrawableContainerIdentifier != containerIdentifier
        let sizeChanged = hasSignificantContainerSizeChange(to: containerSize)
        let canRebindForSizeChange = canRebindDrawableForSizeChange()
        lastAttachedContainer = container
        lastDrawableContainerIdentifier = containerIdentifier
        lastDrawableContainerSize = containerSize
        let shouldRebind = containerChanged || (sizeChanged && canRebindForSizeChange) || persistentDrawableView.superview !== container || mediaPlayer.drawable == nil

        if persistentDrawableView.superview !== container {
            persistentDrawableView.removeFromSuperview()
            persistentDrawableView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(persistentDrawableView)
            NSLayoutConstraint.activate([
                persistentDrawableView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                persistentDrawableView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                persistentDrawableView.topAnchor.constraint(equalTo: container.topAnchor),
                persistentDrawableView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            container.layoutSubtreeIfNeeded()
        }

        guard shouldRebind else { return }

        cancelScheduledRebinds()
        refreshDrawableBinding()
        scheduleDelayedDrawableRebind(for: container)
        resumePlaybackAfterDrawableRebindIfNeeded()
    }
    
    func detachDrawable(from container: NSView) {
        if lastAttachedContainer === container {
            lastAttachedContainer = nil
            lastDrawableContainerIdentifier = nil
            lastDrawableContainerSize = .zero
        }
        cancelScheduledRebinds()
        if persistentDrawableView.superview === container {
            persistentDrawableView.removeFromSuperview()
        }
    }
    #else
    func attachDrawable(to container: UIView) {
        #if os(iOS)
        if let preferred = preferredDrawableContainer,
           preferred !== container {
            if preferred.superview != nil, preferred.window != nil {
                return
            }
            preferredDrawableContainer = nil
        }
        #endif
        let containerIdentifier = ObjectIdentifier(container)
        let containerSize = container.bounds.size
        let containerChanged = lastDrawableContainerIdentifier != containerIdentifier
        let sizeChanged = hasSignificantContainerSizeChange(to: containerSize)
        let canRebindForSizeChange = canRebindDrawableForSizeChange()
        lastAttachedContainer = container
        lastDrawableContainerIdentifier = containerIdentifier
        lastDrawableContainerSize = containerSize
        let shouldRebind = containerChanged || (sizeChanged && canRebindForSizeChange) || persistentDrawableView.superview !== container || mediaPlayer.drawable == nil

        if persistentDrawableView.superview !== container {
            persistentDrawableView.removeFromSuperview()
            persistentDrawableView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(persistentDrawableView)
            NSLayoutConstraint.activate([
                persistentDrawableView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                persistentDrawableView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                persistentDrawableView.topAnchor.constraint(equalTo: container.topAnchor),
                persistentDrawableView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            container.layoutIfNeeded()
        }

        guard shouldRebind else { return }

        cancelScheduledRebinds()
        refreshDrawableBinding()
        scheduleDelayedDrawableRebind(for: container)
        resumePlaybackAfterDrawableRebindIfNeeded()
    }
    
    func detachDrawable(from container: UIView) {
        if lastAttachedContainer === container {
            lastAttachedContainer = nil
            lastDrawableContainerIdentifier = nil
            lastDrawableContainerSize = .zero
        }
        cancelScheduledRebinds()
        if persistentDrawableView.superview === container {
            persistentDrawableView.removeFromSuperview()
        }
        #if os(iOS)
        if preferredDrawableContainer === container {
            preferredDrawableContainer = nil
        }
        #endif
    }

    #if os(iOS)
    func setPreferredDrawableContainer(_ container: UIView?) {
        preferredDrawableContainer = container
        if let container = container {
            attachDrawable(to: container)
        } else if let lastContainer = lastAttachedContainer, lastContainer.superview != nil {
            refreshDrawableBinding()
            scheduleDelayedDrawableRebind(for: lastContainer)
            resumePlaybackAfterDrawableRebindIfNeeded()
        }
    }
    #endif
    #endif

    private func refreshDrawableBinding() {
        // 强制重绑视频输出，规避 macOS 切全屏后偶发“有声音无画面”
        mediaPlayer.drawable = nil
        mediaPlayer.drawable = persistentDrawableView
        lastDrawableRebindAt = Date()
    }

    private func stopMediaPlayer() {
        // 优先走 libvlc 异步 stop，避免菜单切换时主线程被同步 stop 卡住。
        if let playerPointer = playerInstancePointer(),
           let stopAsync = Self.libVLCStopAsync {
            stopAsync(playerPointer)
            return
        }
        mediaPlayer.stop()
    }

    private func playerInstancePointer() -> UnsafeMutableRawPointer? {
        let selector = Self.playerInstanceSelector
        guard mediaPlayer.responds(to: selector) else { return nil }
        typealias PlayerInstanceGetter = @convention(c) (AnyObject, Selector) -> UnsafeMutableRawPointer?
        let imp = mediaPlayer.method(for: selector)
        let getter = unsafeBitCast(imp, to: PlayerInstanceGetter.self)
        return getter(mediaPlayer, selector)
    }

    private func cancelScheduledRebinds() {
        rebindWorkItems.forEach { $0.cancel() }
        rebindWorkItems.removeAll()
    }

    private func hasSignificantContainerSizeChange(to newSize: CGSize) -> Bool {
        let previousSize = lastDrawableContainerSize
        guard previousSize != .zero else { return false }
        let widthChanged = abs(newSize.width - previousSize.width) > Self.drawableSizeChangeThreshold
        let heightChanged = abs(newSize.height - previousSize.height) > Self.drawableSizeChangeThreshold
        return widthChanged || heightChanged
    }

    private func canRebindDrawableForSizeChange() -> Bool {
        Date().timeIntervalSince(lastDrawableRebindAt) >= Self.drawableRebindMinimumInterval
    }

    private func resumePlaybackAfterDrawableRebindIfNeeded() {
        guard mediaPlayer.media != nil else { return }
        if !mediaPlayer.isPlaying,
           mediaPlayer.state != .opening,
           mediaPlayer.state != .buffering {
            mediaPlayer.play()
        }
        applyPlaybackRate()
    }

    #if os(macOS)
    private func scheduleDelayedDrawableRebind(for container: NSView) {
        [0.05, 0.18].forEach { delay in
            let workItem = DispatchWorkItem { [weak self, weak container] in
                guard let self, let container else { return }
                guard self.lastAttachedContainer === container else { return }
                guard self.persistentDrawableView.superview === container else { return }
                self.refreshDrawableBinding()
                self.resumePlaybackAfterDrawableRebindIfNeeded()
            }
            rebindWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    #else
    private func scheduleDelayedDrawableRebind(for container: UIView) {
        [0.05, 0.18].forEach { delay in
            let workItem = DispatchWorkItem { [weak self, weak container] in
                guard let self, let container else { return }
                guard self.lastAttachedContainer === container else { return }
                guard self.persistentDrawableView.superview === container else { return }
                self.refreshDrawableBinding()
                self.resumePlaybackAfterDrawableRebindIfNeeded()
            }
            rebindWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    #endif
    
    func seek(by offset: Double) {
        guard !isLive else { return }
        var target = max(currentTimeSeconds + offset, 0)
        if hasValidDuration {
            target = min(target, durationSeconds)
        }
        seek(to: target)
    }
    
    func seek(to seconds: Double) {
        guard !isLive else { return }
        let maxSeconds = min(durationSeconds > 0 ? durationSeconds : Double(Int32.max) / 1000.0, Double(Int32.max) / 1000.0)
        let value = max(0, min(seconds, maxSeconds))
        mediaPlayer.time = VLCTime(int: Int32(value * 1000.0))
        emitProgress()
    }
    
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            self?.handlePlayerStateChanged()
        }
    }
    
    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        // 使用定时器统一采样进度，避免 VLC 高频 time 回调带来主线程负载。
    }
    
    private func handlePlayerStateChanged() {
        switch mediaPlayer.state {
        case .opening, .buffering:
            handleBufferingState()
        case .playing:
            handlePlayingState()
        case .paused:
            isInBufferingState = false
            cancelDelayedPreparingIndicator()
            cancelPendingVodBufferingConfirmation()
            setPlaybackStatus(preparing: false, playing: false)
            cancelBufferingFallbackTimer()
        case .ended:
            isInBufferingState = false
            cancelDelayedPreparingIndicator()
            cancelPendingVodBufferingConfirmation()
            setPlaybackStatus(preparing: false, playing: false)
            cancelBufferingFallbackTimer()
            onPlaybackEnded?()
        case .error:
            isInBufferingState = false
            cancelDelayedPreparingIndicator()
            cancelPendingVodBufferingConfirmation()
            setPlaybackStatus(preparing: false, playing: false)
            cancelBufferingFallbackTimer()
            onPlaybackFailed?()
        case .stopped:
            isInBufferingState = false
            cancelDelayedPreparingIndicator()
            cancelPendingVodBufferingConfirmation()
            setPlaybackStatus(preparing: false, playing: false)
            cancelBufferingFallbackTimer()
        default:
            break
        }
    }
    
    private func startProgressTimer() {
        stopProgressTimer()
        let interval = isLive ? progressUpdateIntervalLive : progressUpdateIntervalVod
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.emitProgress()
            }
        }
        timer.tolerance = interval * 0.25
        progressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func applyPendingSeekIfNeeded() {
        guard let pendingSeekSeconds, pendingSeekSeconds > 0 else { return }
        seek(to: pendingSeekSeconds)
        self.pendingSeekSeconds = nil
    }
    
    private func emitProgress() {
        refreshPlaybackFlags()
        guard !isLive else { return }
        let current = currentSeconds()
        guard current.isFinite, current >= 0 else { return }
        
        let roundedCurrent = (current / progressPublishThreshold).rounded() * progressPublishThreshold
        let didUpdateCurrent = abs(roundedCurrent - currentTimeSeconds) >= progressPublishThreshold
        if didUpdateCurrent {
            currentTimeSeconds = roundedCurrent
        }
        
        var didUpdateDuration = false
        if let duration = durationSecondsFromMedia() {
            if abs(duration - durationSeconds) >= durationPublishThreshold {
                durationSeconds = duration
                didUpdateDuration = true
            }
        }
        
        guard didUpdateCurrent || didUpdateDuration else { return }
        onProgressChanged?(currentTimeSeconds, hasValidDuration ? durationSeconds : nil)
    }
    
    private func refreshPlaybackFlags() {
        // 部分直播源会长时间停留在 buffering/opening 回调，但实际已开始渲染。
        // 使用底层 isPlaying 兜底，避免“永远加载中”。
        if mediaPlayer.isPlaying {
            isInBufferingState = false
            cancelDelayedPreparingIndicator()
            cancelPendingVodBufferingConfirmation()
            setPlaybackStatus(preparing: false, playing: true)
            cancelBufferingFallbackTimer()
            return
        }
        
        switch mediaPlayer.state {
        case .opening, .buffering:
            setPlaybackStatus(preparing: true, playing: false)
        case .playing:
            setPlaybackStatus(preparing: false, playing: true)
        case .paused, .stopped, .ended, .error:
            setPlaybackStatus(preparing: false, playing: false)
        default:
            break
        }
    }
    
    private func applyPlaybackRate() {
        guard mediaPlayer.rate != playbackRate else { return }
        mediaPlayer.rate = playbackRate
    }

    private func applyVolume() {
        let target = Int32(volume)
        guard mediaPlayer.audio?.volume != target else { return }
        mediaPlayer.audio?.volume = target
    }
    
    private func syncDecodeModeFromSettings() {
        if let decodeModeOverride {
            decodeMode = decodeModeOverride
            return
        }
        decodeMode = VideoDecodeMode.fromStoredValue(
            UserDefaults.standard.integer(forKey: HawkConfig.PLAY_DECODE_MODE)
        )
    }

    private func syncBufferModeFromSettings() {
        bufferMode = VLCBufferMode.fromStoredValue(
            UserDefaults.standard.integer(forKey: HawkConfig.PLAY_VLC_BUFFER_MODE)
        )
    }
    
    private static func normalizedPlaybackRate(from raw: Float) -> Float {
        guard !supportedPlaybackRates.isEmpty else { return 1.0 }
        return supportedPlaybackRates.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? 1.0
    }

    private static func normalizedVolume(from raw: Int) -> Int {
        min(max(raw, 0), maxVolume)
    }
    
    private static func cacheConfig(isLive: Bool, bufferMode: VLCBufferMode) -> (network: Int, live: Int, file: Int) {
        bufferMode.cacheConfig(isLive: isLive)
    }

    private func scheduleBufferingFallbackIfNeeded() {
        guard isLive else { return }
        guard bufferingFallbackWorkItem == nil else { return }
        guard !hasAttemptedSoftDecodeFallback else { return }
        guard decodeMode != .software else { return }
        guard mediaPlayer.media != nil else { return }

        let delay = bufferingFallbackThresholdLive
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.attemptSoftDecodeFallbackIfNeeded()
            }
        }
        bufferingFallbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelBufferingFallbackTimer() {
        bufferingFallbackWorkItem?.cancel()
        bufferingFallbackWorkItem = nil
    }

    private func attemptSoftDecodeFallbackIfNeeded() {
        cancelBufferingFallbackTimer()
        guard !hasAttemptedSoftDecodeFallback else { return }
        guard decodeMode != .software else { return }
        guard let urlString = currentMediaURLString, let url = URL(string: urlString) else { return }
        guard mediaPlayer.media != nil else { return }

        hasAttemptedSoftDecodeFallback = true
        decodeModeOverride = .software
        let resumePosition = isLive ? 0 : max(currentSeconds(), 0)
        play(
            url: url,
            startPosition: resumePosition,
            isLive: isLive,
            onProgressChanged: onProgressChanged,
            onPlaybackEnded: onPlaybackEnded,
            onPlaybackFailed: onPlaybackFailed
        )
    }

    private func handleBufferingState() {
        if isLive {
            if !isInBufferingState {
                isInBufferingState = true
            }
            setPlaybackStatus(preparing: true, playing: false)
            scheduleBufferingFallbackIfNeeded()
            return
        }

        if isInBufferingState {
            if isPlaying {
                isPlaying = false
            }
            scheduleDelayedPreparingIndicatorForVod()
            return
        }

        scheduleVodBufferingConfirmationIfNeeded()
    }

    private func handlePlayingState() {
        cancelPendingVodBufferingConfirmation()
        isInBufferingState = false
        cancelDelayedPreparingIndicator()
        setPlaybackStatus(preparing: false, playing: true)
        cancelBufferingFallbackTimer()
        applyPlaybackRate()
        applyVolume()
        applyPendingSeekIfNeeded()
    }

    private func scheduleDelayedPreparingIndicatorForVod() {
        guard !isLive else { return }
        guard delayedPreparingWorkItem == nil else { return }
        guard !isPreparing else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isInBufferingState, !self.mediaPlayer.isPlaying else { return }
            guard self.isStillStalledSinceBufferingStartedVod() else { return }
            self.setPlaybackStatus(preparing: true, playing: false)
        }
        delayedPreparingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + bufferingIndicatorDelayVod, execute: workItem)
    }

    private func cancelDelayedPreparingIndicator() {
        delayedPreparingWorkItem?.cancel()
        delayedPreparingWorkItem = nil
    }

    private func scheduleVodBufferingConfirmationIfNeeded() {
        guard !isLive else { return }
        guard pendingVodBufferingConfirmWorkItem == nil else { return }
        bufferingBaselineSecondsVod = max(currentSeconds(), currentTimeSeconds)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingVodBufferingConfirmWorkItem = nil
            guard self.isBufferingLikeState(self.mediaPlayer.state) else { return }
            guard !self.mediaPlayer.isPlaying else { return }
            guard self.isStillStalledSinceBufferingStartedVod() else { return }
            self.enterConfirmedVodBufferingState()
        }
        pendingVodBufferingConfirmWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + bufferingConfirmDelayVod, execute: workItem)
    }

    private func cancelPendingVodBufferingConfirmation() {
        pendingVodBufferingConfirmWorkItem?.cancel()
        pendingVodBufferingConfirmWorkItem = nil
    }

    private func enterConfirmedVodBufferingState() {
        guard !isLive else { return }
        guard !mediaPlayer.isPlaying else { return }
        if !isInBufferingState {
            isInBufferingState = true
        }
        if isPlaying {
            isPlaying = false
        }
        scheduleDelayedPreparingIndicatorForVod()
    }

    private func isStillStalledSinceBufferingStartedVod() -> Bool {
        let current = max(currentSeconds(), currentTimeSeconds)
        return (current - bufferingBaselineSecondsVod) < vodBufferingProgressAdvanceThreshold
    }

    private func isBufferingLikeState(_ state: VLCMediaPlayerState) -> Bool {
        switch state {
        case .opening, .buffering:
            return true
        default:
            return false
        }
    }

    private func resetPlaybackRecoveryState() {
        cancelBufferingFallbackTimer()
        cancelDelayedPreparingIndicator()
        cancelPendingVodBufferingConfirmation()
        hasAttemptedSoftDecodeFallback = false
        decodeModeOverride = nil
        isInBufferingState = false
        bufferingBaselineSecondsVod = 0
    }
    
    private func setPlaybackStatus(preparing: Bool, playing: Bool) {
        if isPreparing != preparing {
            isPreparing = preparing
        }
        if isPlaying != playing {
            isPlaying = playing
        }
    }
    
    private func resetProgressState() {
        if currentTimeSeconds != 0 {
            currentTimeSeconds = 0
        }
        if durationSeconds != 0 {
            durationSeconds = 0
        }
    }
    
    private func currentSeconds() -> Double {
        let raw = mediaPlayer.time.intValue
        if raw < 0 { return 0 }
        return Double(raw) / 1000.0
    }
    
    private func durationSecondsFromMedia() -> Double? {
        let raw = mediaPlayer.media?.length.intValue ?? 0
        guard raw > 0 else { return nil }
        return Double(raw) / 1000.0
    }
}

struct VLCVodPlayerView: View {
    let urlString: String
    var startPosition: Double = 0
    var httpHeaders: [String: String] = [:]
    var onProgressChanged: ((Double, Double?) -> Void)? = nil
    var onPlaybackEnded: (() -> Void)? = nil
    var onToggleFullScreen: (() -> Void)? = nil
    var canPlayNext: Bool = false
    var onPlayNext: (() -> Void)? = nil
    var canPlayPrevious: Bool = false
    var onPlayPrevious: (() -> Void)? = nil
    var onSetVideoFit: (VideoFitType) -> Void = { _ in }
    var onTogglePiP: () -> Void = {}
    var onCast: () -> Void = {}
    var sharedController: VLCPlayerController? = nil
    var isFullScreenMode: Bool = false
    var videoTitle: String = ""
    var currentEpisodeName: String = ""
    var showEpisodeButton: Bool = false
    var onShowEpisodes: (() -> Void)? = nil
    var onSwitchPlayer: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    @StateObject private var ownedController = VLCPlayerController()
    @StateObject private var gestureDelegate = PlayerGestureDelegate()
    @State private var isDraggingProgress = false
    @State private var draggingSeconds: Double = 0
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var startPlaybackTask: Task<Void, Never>?
    @State private var isLocked = false
    @State private var savedPlaybackRateBeforeLongPress: Float = 1.0
    @State private var sliderTempPosition: Double = 0
    @State private var skipIntroSeconds: Int = 0
    @State private var skipOutroSeconds: Int = 0
    @State private var showSettingsSheet: Bool = false
    @State private var videoFitType: VideoFitType = .contain
    @State private var vlcBitrateText: String = ""
    @State private var vlcBitrateTimer: Timer?

    private var controller: VLCPlayerController {
        sharedController ?? ownedController
    }

    private var currentResolution: String {
        let w = controller.videoWidth
        let h = controller.videoHeight
        if w > 0 && h > 0 { return "\(w)x\(h)" }
        return ""
    }

    private var currentBitrate: String {
        return vlcBitrateText
    }

    var body: some View {
        ZStack {
            VLCDrawableView(controller: controller, isFullScreenMode: isFullScreenMode, videoFitType: videoFitType)
                .background(Color.black)

            if controller.isPreparing {
                ProgressView()
                    .tint(.white)
            }

            #if os(iOS)
            PlayerGestureOverlay(delegate: gestureDelegate)
            #endif

            if !isLocked {
                DoubleTapSeekIndicatorView(
                    isForward: false,
                    seconds: gestureDelegate.seekAccumulatedSeconds,
                    isVisible: gestureDelegate.showBackwardSeek
                )

                DoubleTapSeekIndicatorView(
                    isForward: true,
                    seconds: gestureDelegate.seekAccumulatedSeconds,
                    isVisible: gestureDelegate.showForwardSeek
                )
            }

            VStack(spacing: 0) {
                VolumeBrightnessIndicator(
                    type: .brightness,
                    value: gestureDelegate.brightnessValue,
                    isVisible: gestureDelegate.showBrightnessIndicator
                )

                Spacer()

                HStack(spacing: 16) {
                    VolumeBrightnessIndicator(
                        type: .volume,
                        value: gestureDelegate.volumeValue,
                        isVisible: gestureDelegate.showVolumeIndicator
                    )

                    LongPressSpeedIndicator(
                        speed: gestureDelegate.longPressSpeed,
                        isVisible: gestureDelegate.showLongPressIndicator
                    )
                }
                .padding(.bottom, 80)
            }
            .allowsHitTesting(false)

            #if os(macOS)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControls()
                }
            #endif
        }
        .overlay {
            PlayerControlsOverlay(
                isPlaying: controller.isPlaying,
                isPreparing: controller.isPreparing,
                currentTime: controller.currentTimeSeconds,
                duration: controller.durationSeconds,
                hasValidDuration: controller.hasValidDuration,
                isDraggingProgress: isDraggingProgress,
                draggingSeconds: draggingSeconds,
                playbackRate: controller.playbackRate,
                isFullScreen: isFullScreenMode,
                isLocked: isLocked,
                canPlayNext: canPlayNext,
                canPlayPrevious: canPlayPrevious,
                showControls: showControls,
                volumeIconName: volumeIconName,
                seekStep: seekStep,
                videoTitle: videoTitle,
                currentEpisodeName: currentEpisodeName,
                currentResolution: currentResolution,
                currentBitrate: currentBitrate,
                showEpisodeButton: showEpisodeButton,
                showPlayerSwitchButton: PlayerEngine.isVLCAvailable,
                skipIntroSeconds: skipIntroSeconds,
                skipOutroSeconds: skipOutroSeconds,
                currentPlaybackEngine: .vlc,
                onTogglePlayPause: { wakeUpControls(); togglePlayback() },
                onSeekBackward: { controller.seek(by: -seekStep) },
                onSeekForward: { controller.seek(by: seekStep) },
                onPlayNext: { onPlayNext?() },
                onPlayPrevious: { onPlayPrevious?() },
                onToggleMute: { controller.toggleMute() },
                onToggleFullScreen: { onToggleFullScreen?() },
                onProgressDragChanged: { newValue in
                    draggingSeconds = newValue
                    sliderTempPosition = newValue
                    isDraggingProgress = true
                    wakeUpControls()
                },
                onProgressDragEnded: { editing in
                    isDraggingProgress = editing
                    wakeUpControls()
                    if !editing {
                        controller.seek(to: draggingSeconds)
                    }
                },
                onSetPlaybackRate: { rate in
                    controller.setPlaybackRate(rate)
                },
                onToggleLock: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isLocked.toggle()
                    }
                    if isLocked {
                        hideControls()
                    } else {
                        wakeUpControls()
                    }
                },
                onWakeUpControls: { wakeUpControls() },
                onShowEpisodes: { onShowEpisodes?() },
                onSwitchPlayer: { onSwitchPlayer?() },
                onSkipIntro: {
                    if skipIntroSeconds > 0 {
                        controller.seek(to: Double(skipIntroSeconds))
                    }
                },
                onSkipOutro: {
                    if skipOutroSeconds > 0, controller.hasValidDuration {
                        controller.seek(to: controller.durationSeconds - Double(skipOutroSeconds))
                    }
                },
                onShowSettings: {
                    showSettingsSheet = true
                },
                videoFitType: videoFitType,
                onSetVideoFit: { videoFitType = $0 },
                onTogglePiP: {},
                onCast: {},
                onBack: { onBack?() }
            )
        }
        .overlay {
            KeyboardShortcutCaptureView(
                onLeft: { wakeUpControls(); controller.seek(by: -seekStep) },
                onRight: { wakeUpControls(); controller.seek(by: seekStep) },
                onTogglePlayPause: { wakeUpControls(); togglePlayback() },
                onToggleFullScreen: { wakeUpControls(); onToggleFullScreen?() },
                onDecreaseSpeed: { wakeUpControls(); controller.decreasePlaybackRate() },
                onIncreaseSpeed: { wakeUpControls(); controller.increasePlaybackRate() },
                onVolumeDown: {
                    wakeUpControls()
                    controller.setVolume(controller.volume - volumeStep)
                },
                onVolumeUp: {
                    wakeUpControls()
                    controller.setVolume(controller.volume + volumeStep)
                }
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
            setupGestureCallbacks()
            startPlayback()
            startVLCBitrateMonitor()
            wakeUpControls()
        }
        .onChange(of: urlString) { _ in
            startPlayback()
            wakeUpControls()
        }
        .onChange(of: controller.currentTimeSeconds) { newValue in
            if !isDraggingProgress {
                draggingSeconds = newValue
                sliderTempPosition = newValue
            }
        }
        .onDisappear {
            startPlaybackTask?.cancel()
            startPlaybackTask = nil
            stopVLCBitrateMonitor()
            if sharedController == nil {
                controller.stop()
            }
            #if os(iOS)
            if isFullScreenMode {
                controller.setPreferredDrawableContainer(nil)
            }
            #endif
            controlsTimer?.invalidate()
        }
        .sheet(isPresented: $showSettingsSheet) {
            PlayerSettingsSheet(
                currentPlaybackEngine: .vlc,
                skipIntroSeconds: skipIntroSeconds,
                skipOutroSeconds: skipOutroSeconds,
                playbackRate: controller.playbackRate,
                currentResolution: currentResolution,
                currentBitrate: currentBitrate,
                onSwitchPlayer: { onSwitchPlayer?() },
                onSetPlaybackRate: { rate in
                    controller.setPlaybackRate(rate)
                },
                onSetSkipIntro: { seconds in
                    skipIntroSeconds = seconds
                },
                onSetSkipOutro: { seconds in
                    skipOutroSeconds = seconds
                },
                videoFitType: videoFitType,
                onSetVideoFit: { videoFitType = $0 },
                onShowPlayerInfo: {}
            )
        }
    }

    #if os(iOS)
    private func setupGestureCallbacks() {
        gestureDelegate.isLive = false
        gestureDelegate.fastForBackwardDuration = Int(seekStep)

        gestureDelegate.onToggleControls = {
            toggleControls()
        }

        gestureDelegate.onDoubleTap = { zone in
            switch zone {
            case .left:
                gestureDelegate.showBackwardSeek = true
                gestureDelegate.seekAccumulatedSeconds = Int(seekStep)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if gestureDelegate.showBackwardSeek {
                        controller.seek(by: -seekStep)
                        gestureDelegate.showBackwardSeek = false
                    }
                }
            case .center:
                togglePlayback()
            case .right:
                gestureDelegate.showForwardSeek = true
                gestureDelegate.seekAccumulatedSeconds = Int(seekStep)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if gestureDelegate.showForwardSeek {
                        controller.seek(by: seekStep)
                        gestureDelegate.showForwardSeek = false
                    }
                }
            }
        }

        gestureDelegate.onLongPressStart = {
            savedPlaybackRateBeforeLongPress = controller.playbackRate
            gestureDelegate.longPressSpeed = controller.playbackRate * 2
            controller.setPlaybackRate(controller.playbackRate * 2)
            gestureDelegate.showLongPressIndicator = true
        }

        gestureDelegate.onLongPressEnd = {
            controller.setPlaybackRate(savedPlaybackRateBeforeLongPress)
            gestureDelegate.showLongPressIndicator = false
        }

        gestureDelegate.onHorizontalSeek = { delta in
            let scale = controller.durationSeconds > 0 ? controller.durationSeconds * 0.3 : 300
            let seekDelta = Double(delta) / UIScreen.main.bounds.width * scale
            sliderTempPosition = max(0, sliderTempPosition + seekDelta)
            if controller.hasValidDuration {
                sliderTempPosition = min(sliderTempPosition, controller.durationSeconds)
            }
            draggingSeconds = sliderTempPosition
            isDraggingProgress = true
        }

        gestureDelegate.onVolumeChange = { newVolume in
            let targetVolume = Int(newVolume * 200)
            controller.setVolume(targetVolume)
        }

        gestureDelegate.onFullScreenGesture = { enterFullScreen in
            if enterFullScreen == isFullScreenMode {
                return
            }
            onToggleFullScreen?()
        }

        gestureDelegate.onGestureEnd = {
            if isDraggingProgress {
                controller.seek(to: draggingSeconds)
                isDraggingProgress = false
            }
        }
    }
    #else
    private func setupGestureCallbacks() {}
    #endif

    private var volumeIconName: String {
        switch controller.volume {
        case ...0: return "speaker.slash.fill"
        case 1...66: return "speaker.wave.1.fill"
        default: return "speaker.wave.2.fill"
        }
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

    private func togglePlayback() {
        controller.togglePlayback()
        wakeUpControls()
    }

    private func hideControls() {
        withAnimation(.easeOut(duration: 0.3)) {
            showControls = false
        }
        controlsTimer?.invalidate()
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

    private func startPlayback() {
        guard let url = URL(string: urlString) else { return }
        let targetStartPosition = max(startPosition, 0)
        draggingSeconds = targetStartPosition
        startPlaybackTask?.cancel()
        startPlaybackTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            controller.play(
                url: url,
                startPosition: targetStartPosition,
                isLive: false,
                onProgressChanged: onProgressChanged,
                onPlaybackEnded: onPlaybackEnded,
                onPlaybackFailed: nil,
                httpHeaders: httpHeaders
            )
        }
    }

    private var seekStep: Double {
        let saved = UserDefaults.standard.integer(forKey: HawkConfig.PLAY_TIME_STEP)
        return Double(saved > 0 ? saved : 10)
    }

    private var volumeStep: Int { 10 }

    private func startVLCBitrateMonitor() {
        vlcBitrateTimer?.invalidate()
        var lastBytes: Int64 = 0
        var lastTime: Date = Date()
        vlcBitrateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let stats = controller.mediaPlayer.statistics
                let currentBytes = stats.videoDecodedVideoBytes + stats.videoDecodedTextBytes
                let now = Date()
                let interval = now.timeIntervalSince(lastTime)
                if interval > 0 {
                    let bytesPerSec = Double(currentBytes - lastBytes) / interval
                    if bytesPerSec > 0 {
                        let mbps = bytesPerSec * 8 / 1_000_000.0
                        if mbps >= 1.0 {
                            vlcBitrateText = String(format: "%.1fMbps", mbps)
                        } else {
                            let kbps = bytesPerSec * 8 / 1_000.0
                            vlcBitrateText = String(format: "%.0fKbps", kbps)
                        }
                    }
                }
                lastBytes = currentBytes
                lastTime = now
            }
        }
    }

    private func stopVLCBitrateMonitor() {
        vlcBitrateTimer?.invalidate()
        vlcBitrateTimer = nil
        vlcBitrateText = ""
    }

    private var progressUpperBound: Double {
        max(controller.durationSeconds, max(controller.currentTimeSeconds, 1))
    }

    private var currentDisplaySeconds: Double {
        isDraggingProgress ? draggingSeconds : controller.currentTimeSeconds
    }

    private var totalDisplayText: String {
        controller.hasValidDuration ? controller.durationSeconds.durationString : "--:--"
    }
}

struct VLCLivePlayerView: View {
    let urlString: String
    var activityToken: Int = 0
    var onPlaybackFailed: (() -> Void)? = nil
    var onToggleFullScreen: (() -> Void)? = nil
    @StateObject private var controller = VLCPlayerController()
    private var volumeStep: Int { 10 }
    
    @State private var osdIcon: String?
    @State private var osdOpacity: Double = 0
    @State private var osdTimer: Timer?
    
    var body: some View {
        ZStack {
            VLCDrawableView(controller: controller)
                .background(Color.black)
                .onTapGesture(count: 2) {
                    onToggleFullScreen?()
                }
                .onTapGesture(count: 1) {
                    togglePlaybackWithOSD()
                }
            
            if controller.isPreparing {
                ProgressView()
                    .tint(.white)
            }
            
            if let osdIcon = osdIcon {
                Image(systemName: osdIcon)
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(30)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .opacity(osdOpacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            KeyboardShortcutCaptureView(
                onLeft: { },
                onRight: { },
                onTogglePlayPause: { togglePlaybackWithOSD() },
                onToggleFullScreen: { onToggleFullScreen?() },
                onDecreaseSpeed: { },
                onIncreaseSpeed: { },
                onVolumeDown: {
                    controller.setVolume(controller.volume - volumeStep)
                    showOSD(icon: controller.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                },
                onVolumeUp: {
                    controller.setVolume(controller.volume + volumeStep)
                    showOSD(icon: controller.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
        }
        .onAppear {
            startPlayback()
        }
        .onChange(of: urlString) { _ in
            startPlayback()
        }
        .onDisappear {
            controller.stop()
            osdTimer?.invalidate()
        }
    }
    
    private func showOSD(icon: String) {
        osdIcon = icon
        osdOpacity = 1.0
        osdTimer?.invalidate()
        osdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.5)) {
                osdOpacity = 0.0
            }
        }
    }
    
    private func togglePlaybackWithOSD() {
        controller.togglePlayback()
        showOSD(icon: controller.isPlaying ? "pause.fill" : "play.fill")
    }
    
    private func startPlayback() {
        guard let url = URL(string: urlString) else {
            onPlaybackFailed?()
            return
        }
        controller.play(
            url: url,
            startPosition: 0,
            isLive: true,
            onProgressChanged: nil,
            onPlaybackEnded: nil,
            onPlaybackFailed: onPlaybackFailed
        )
    }
}

private struct VLCDrawableView: View {
    let controller: VLCPlayerController
    var isFullScreenMode: Bool = false
    var videoFitType: VideoFitType = .contain

    var body: some View {
        #if os(macOS)
        VLCMacDrawableView(controller: controller)
        #else
        VLCIOSDrawableView(controller: controller, isFullScreenMode: isFullScreenMode, videoFitType: videoFitType)
        #endif
    }
}

private struct KeyboardShortcutCaptureView: View {
    let onLeft: () -> Void
    let onRight: () -> Void
    let onTogglePlayPause: () -> Void
    let onToggleFullScreen: () -> Void
    let onDecreaseSpeed: () -> Void
    let onIncreaseSpeed: () -> Void
    let onVolumeDown: () -> Void
    let onVolumeUp: () -> Void
    
    var body: some View {
        #if os(macOS)
        MacKeyboardCaptureView(
            onLeft: onLeft,
            onRight: onRight,
            onTogglePlayPause: onTogglePlayPause,
            onToggleFullScreen: onToggleFullScreen,
            onDecreaseSpeed: onDecreaseSpeed,
            onIncreaseSpeed: onIncreaseSpeed,
            onVolumeDown: onVolumeDown,
            onVolumeUp: onVolumeUp
        )
        #else
        IOSKeyboardCaptureView(
            onLeft: onLeft,
            onRight: onRight,
            onTogglePlayPause: onTogglePlayPause,
            onToggleFullScreen: onToggleFullScreen,
            onDecreaseSpeed: onDecreaseSpeed,
            onIncreaseSpeed: onIncreaseSpeed,
            onVolumeDown: onVolumeDown,
            onVolumeUp: onVolumeUp
        )
        #endif
    }
}

#if os(macOS)
private struct VLCMacDrawableView: NSViewRepresentable {
    let controller: VLCPlayerController
    
    final class Coordinator {
        let controller: VLCPlayerController
        
        init(controller: VLCPlayerController) {
            self.controller = controller
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }
    
    func makeNSView(context: Context) -> VLCOutputNSView {
        let view = VLCOutputNSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.onLifecycle = { container in
            context.coordinator.controller.attachDrawable(to: container)
        }
        view.requestLifecycleUpdate()
        return view
    }
    
    func updateNSView(_ nsView: VLCOutputNSView, context: Context) {
        nsView.onLifecycle = { container in
            context.coordinator.controller.attachDrawable(to: container)
        }
        nsView.requestLifecycleUpdate()
    }
    
    static func dismantleNSView(_ nsView: VLCOutputNSView, coordinator: Coordinator) {
        nsView.onLifecycle = nil
        coordinator.controller.detachDrawable(from: nsView)
    }
}

private final class VLCOutputNSView: NSView {
    var onLifecycle: ((NSView) -> Void)?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestLifecycleUpdate()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        requestLifecycleUpdate()
    }
    
    override func layout() {
        super.layout()
        requestLifecycleUpdate()
    }
    
    func requestLifecycleUpdate() {
        onLifecycle?(self)
    }
}

private struct MacKeyboardCaptureView: NSViewRepresentable {
    let onLeft: () -> Void
    let onRight: () -> Void
    let onTogglePlayPause: () -> Void
    let onToggleFullScreen: () -> Void
    let onDecreaseSpeed: () -> Void
    let onIncreaseSpeed: () -> Void
    let onVolumeDown: () -> Void
    let onVolumeUp: () -> Void
    
    func makeNSView(context: Context) -> MacKeyCaptureNSView {
        let view = MacKeyCaptureNSView(frame: .zero)
        applyCallbacks(to: view)
        DispatchQueue.main.async {
            view.activate()
        }
        return view
    }
    
    func updateNSView(_ nsView: MacKeyCaptureNSView, context: Context) {
        applyCallbacks(to: nsView)
        DispatchQueue.main.async {
            nsView.activate()
        }
    }
    
    private func applyCallbacks(to view: MacKeyCaptureNSView) {
        view.onLeft = onLeft
        view.onRight = onRight
        view.onTogglePlayPause = onTogglePlayPause
        view.onToggleFullScreen = onToggleFullScreen
        view.onDecreaseSpeed = onDecreaseSpeed
        view.onIncreaseSpeed = onIncreaseSpeed
        view.onVolumeDown = onVolumeDown
        view.onVolumeUp = onVolumeUp
    }
}

private final class MacKeyCaptureNSView: NSView {
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?
    var onDecreaseSpeed: (() -> Void)?
    var onIncreaseSpeed: (() -> Void)?
    var onVolumeDown: (() -> Void)?
    var onVolumeUp: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activate()
    }
    
    func activate() {
        window?.makeFirstResponder(self)
    }
    
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false {
            super.keyDown(with: event)
            return
        }
        
        switch event.keyCode {
        case 123: // left
            onLeft?()
            return
        case 124: // right
            onRight?()
            return
        case 125: // down
            onVolumeDown?()
            return
        case 126: // up
            onVolumeUp?()
            return
        case 49: // space
            onTogglePlayPause?()
            return
        default:
            break
        }
        
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch key {
        case "k":
            onTogglePlayPause?()
        case "f":
            onToggleFullScreen?()
        case "[":
            onDecreaseSpeed?()
        case "]":
            onIncreaseSpeed?()
        default:
            super.keyDown(with: event)
        }
    }
}
#else
private struct VLCIOSDrawableView: UIViewRepresentable {
    let controller: VLCPlayerController
    var isFullScreenMode: Bool = false
    var videoFitType: VideoFitType = .contain

    final class Coordinator {
        let controller: VLCPlayerController

        init(controller: VLCPlayerController) {
            self.controller = controller
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> VLCOutputUIView {
        let view = VLCOutputUIView(frame: .zero)
        view.backgroundColor = .black
        view.contentMode = videoFitType.uiContentMode
        view.onLifecycle = { container in
            context.coordinator.controller.attachDrawable(to: container)
        }
        if isFullScreenMode {
            controller.setPreferredDrawableContainer(view)
        }
        view.requestLifecycleUpdate()
        return view
    }

    func updateUIView(_ uiView: VLCOutputUIView, context: Context) {
        uiView.contentMode = videoFitType.uiContentMode
        uiView.onLifecycle = { container in
            context.coordinator.controller.attachDrawable(to: container)
        }
        if isFullScreenMode {
            controller.setPreferredDrawableContainer(uiView)
        }
        uiView.requestLifecycleUpdate()
    }
    
    static func dismantleUIView(_ uiView: VLCOutputUIView, coordinator: Coordinator) {
        uiView.onLifecycle = nil
        coordinator.controller.detachDrawable(from: uiView)
    }
}

private final class VLCOutputUIView: UIView {
    var onLifecycle: ((UIView) -> Void)?
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        requestLifecycleUpdate()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        requestLifecycleUpdate()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        requestLifecycleUpdate()
    }
    
    func requestLifecycleUpdate() {
        onLifecycle?(self)
    }
}

private struct IOSKeyboardCaptureView: UIViewRepresentable {
    let onLeft: () -> Void
    let onRight: () -> Void
    let onTogglePlayPause: () -> Void
    let onToggleFullScreen: () -> Void
    let onDecreaseSpeed: () -> Void
    let onIncreaseSpeed: () -> Void
    let onVolumeDown: () -> Void
    let onVolumeUp: () -> Void
    
    func makeUIView(context: Context) -> IOSKeyCaptureView {
        let view = IOSKeyCaptureView(frame: .zero)
        applyCallbacks(to: view)
        DispatchQueue.main.async {
            view.activate()
        }
        return view
    }
    
    func updateUIView(_ uiView: IOSKeyCaptureView, context: Context) {
        applyCallbacks(to: uiView)
        DispatchQueue.main.async {
            uiView.activate()
        }
    }
    
    private func applyCallbacks(to view: IOSKeyCaptureView) {
        view.onLeft = onLeft
        view.onRight = onRight
        view.onTogglePlayPause = onTogglePlayPause
        view.onToggleFullScreen = onToggleFullScreen
        view.onDecreaseSpeed = onDecreaseSpeed
        view.onIncreaseSpeed = onIncreaseSpeed
        view.onVolumeDown = onVolumeDown
        view.onVolumeUp = onVolumeUp
    }
}

private final class IOSKeyCaptureView: UIView {
    var onLeft: (() -> Void)?
    var onRight: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?
    var onDecreaseSpeed: (() -> Void)?
    var onIncreaseSpeed: (() -> Void)?
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
            UIKeyCommand(input: "f", modifierFlags: [], action: #selector(handleToggleFullScreen)),
            UIKeyCommand(input: "[", modifierFlags: [], action: #selector(handleDecreaseSpeed)),
            UIKeyCommand(input: "]", modifierFlags: [], action: #selector(handleIncreaseSpeed))
        ]
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        activate()
    }
    
    func activate() {
        becomeFirstResponder()
    }
    
    @objc private func handleLeft() {
        onLeft?()
    }
    
    @objc private func handleRight() {
        onRight?()
    }
    
    @objc private func handleTogglePlayPause() {
        onTogglePlayPause?()
    }
    
    @objc private func handleToggleFullScreen() {
        onToggleFullScreen?()
    }
    
    @objc private func handleDecreaseSpeed() {
        onDecreaseSpeed?()
    }
    
    @objc private func handleIncreaseSpeed() {
        onIncreaseSpeed?()
    }

    @objc private func handleVolumeDown() {
        onVolumeDown?()
    }

    @objc private func handleVolumeUp() {
        onVolumeUp?()
    }
}
#endif

#else

final class VLCPlayerController: ObservableObject {
    func stop() {}
}

struct VLCVodPlayerView: View {
    let urlString: String
    var startPosition: Double = 0
    var onProgressChanged: ((Double, Double?) -> Void)? = nil
    var onPlaybackEnded: (() -> Void)? = nil
    var onToggleFullScreen: (() -> Void)? = nil
    var canPlayNext: Bool = false
    var onPlayNext: (() -> Void)? = nil
    
    var body: some View {
        AVPlayerContentView(
            urlString: urlString,
            startPosition: startPosition,
            onProgressChanged: onProgressChanged,
            onPlaybackEnded: onPlaybackEnded,
            onToggleFullScreen: onToggleFullScreen,
            canPlayNext: canPlayNext,
            onPlayNext: onPlayNext
        )
    }
}

struct VLCLivePlayerView: View {
    let urlString: String
    var onPlaybackFailed: (() -> Void)? = nil
    var onToggleFullScreen: (() -> Void)? = nil
    
    var body: some View {
        Color.black
    }
}

#endif
