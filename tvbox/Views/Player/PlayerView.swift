import SwiftUI
import AVKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PlatformVideoPlayer: View {
    let player: AVPlayer
    var videoFitType: VideoFitType = .contain
    var pipManager: PlayerPiPManager? = nil

    var body: some View {
        #if os(macOS)
        MacOSPlayerView(player: player, videoGravity: videoFitType.avVideoGravity)
        #else
        IOSPlayerView(player: player, videoGravity: videoFitType.avVideoGravity, pipManager: pipManager)
        #endif
    }
}

#if os(macOS)
private struct MacOSPlayerView: NSViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.videoGravity = videoGravity
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.videoGravity = videoGravity
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player = nil
    }
}
#else

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private final class PlayerHostingViewController: UIViewController {
    var player: AVPlayer? {
        didSet { playerView.playerLayer.player = player }
    }
    var videoGravity: AVLayerVideoGravity = .resizeAspect {
        didSet { playerView.playerLayer.videoGravity = videoGravity }
    }
    weak var pipManager: PlayerPiPManager?

    private let playerView = PlayerLayerView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(playerView)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.backgroundColor = .black
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        playerView.playerLayer.videoGravity = videoGravity
        playerView.playerLayer.player = player
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerView.playerLayer.frame = playerView.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pipManager?.setup(with: playerView.playerLayer)
    }
}

private struct IOSPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var pipManager: PlayerPiPManager?

    func makeUIViewController(context: Context) -> PlayerHostingViewController {
        let vc = PlayerHostingViewController()
        vc.player = player
        vc.videoGravity = videoGravity
        vc.pipManager = pipManager
        return vc
    }

    func updateUIViewController(_ uiViewController: PlayerHostingViewController, context: Context) {
        uiViewController.player = player
        uiViewController.videoGravity = videoGravity
        uiViewController.pipManager = pipManager
    }

    static func dismantleUIViewController(_ uiViewController: PlayerHostingViewController, coordinator: ()) {
        uiViewController.player = nil
    }
}
#endif

@MainActor
final class SystemPlayerSessionController: ObservableObject {
    fileprivate var player: AVPlayer?
    fileprivate var mediaURLString: String?

    func setPlayer(_ newPlayer: AVPlayer, urlString: String) {
        if player !== newPlayer {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
        player = newPlayer
        mediaURLString = urlString
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        mediaURLString = nil
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
    var canPlayPrevious: Bool = false
    var onPlayPrevious: (() -> Void)? = nil
    var systemController: SystemPlayerSessionController? = nil
    var vlcController: VLCPlayerController? = nil
    var isFullScreenMode: Bool = false
    var videoTitle: String = ""
    var currentEpisodeName: String = ""
    var showEpisodeButton: Bool = false
    var onShowEpisodes: (() -> Void)? = nil
    var onSwitchPlayer: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    var httpHeaders: [String: String] = [:]
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
            rawValue = PlayerEngine.isVLCAvailable ? PlayerEngine.vlc.rawValue : PlayerEngine.system.rawValue
        }
        return PlayerEngine.fromStoredValue(rawValue)
    }

    private var effectiveEngine: PlayerEngine {
        if !httpHeaders.isEmpty, PlayerEngine.isVLCAvailable {
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
                    onProgressChanged: onProgressChanged,
                    onPlaybackEnded: onPlaybackEnded,
                    onToggleFullScreen: onToggleFullScreen,
                    canPlayNext: canPlayNext,
                    onPlayNext: onPlayNext,
                    canPlayPrevious: canPlayPrevious,
                    onPlayPrevious: onPlayPrevious,
                    sharedController: systemController,
                    isFullScreenMode: isFullScreenMode,
                    videoTitle: videoTitle,
                    currentEpisodeName: currentEpisodeName,
                    showEpisodeButton: showEpisodeButton,
                    onShowEpisodes: onShowEpisodes,
                    onSwitchPlayer: onSwitchPlayer,
                    onBack: onBack
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
                    canPlayPrevious: canPlayPrevious,
                    onPlayPrevious: onPlayPrevious,
                    sharedController: vlcController,
                    isFullScreenMode: isFullScreenMode,
                    videoTitle: videoTitle,
                    currentEpisodeName: currentEpisodeName,
                    showEpisodeButton: showEpisodeButton,
                    onShowEpisodes: onShowEpisodes,
                    onSwitchPlayer: onSwitchPlayer,
                    onBack: onBack
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

struct AVPlayerContentView: View {
    private static let supportedPlaybackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    let urlString: String
    var startPosition: Double = 0
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
    var sharedController: SystemPlayerSessionController? = nil
    var isFullScreenMode: Bool = false
    var videoTitle: String = ""
    var currentEpisodeName: String = ""
    var showEpisodeButton: Bool = false
    var onShowEpisodes: (() -> Void)? = nil
    var onSwitchPlayer: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    @AppStorage(HawkConfig.PLAY_SPEED) private var savedPlaybackRate = 1.0
    @State private var player: AVPlayer?
    @State private var playbackEndObserver: NSObjectProtocol?
    @State private var timeObserverToken: Any?

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
    @StateObject private var gestureDelegate = PlayerGestureDelegate()
    @State private var isLocked = false
    @State private var savedPlaybackRateBeforeLongPress: Float = 1.0
    @State private var sliderTempPosition: Double = 0
    @State private var skipIntroSeconds: Int = 0
    @State private var skipOutroSeconds: Int = 0
    @State private var showSettingsSheet: Bool = false
    @State private var videoFitType: VideoFitType = .contain
    @StateObject private var networkMonitor = PlayerNetworkMonitor()
    @StateObject private var pipManager = PlayerPiPManager()

    var body: some View {
        ZStack {
            Group {
                if let player = player {
                    PlatformVideoPlayer(player: player, videoFitType: videoFitType, pipManager: pipManager)
                        .onAppear { networkMonitor.attach(to: player) }
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
                isPlaying: isPlaying,
                isPreparing: isPreparing,
                currentTime: currentTime,
                duration: duration,
                hasValidDuration: duration > 0,
                isDraggingProgress: isDraggingProgress,
                draggingSeconds: draggingSeconds,
                playbackRate: rate,
                isFullScreen: isFullScreenMode,
                isLocked: isLocked,
                canPlayNext: canPlayNext,
                canPlayPrevious: canPlayPrevious,
                showControls: showControls,
                volumeIconName: volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill",
                seekStep: seekStep,
                videoTitle: videoTitle,
                currentEpisodeName: currentEpisodeName,
                currentResolution: networkMonitor.resolutionText,
                currentBitrate: networkMonitor.bitrateText,
                showEpisodeButton: showEpisodeButton,
                showPlayerSwitchButton: PlayerEngine.isVLCAvailable,
                skipIntroSeconds: skipIntroSeconds,
                skipOutroSeconds: skipOutroSeconds,
                currentPlaybackEngine: .system,
                videoFitType: videoFitType,
                onTogglePlayPause: { wakeUpControls(); togglePlayPause() },
                onSeekBackward: { seek(by: -seekStep) },
                onSeekForward: { seek(by: seekStep) },
                onPlayNext: { onPlayNext?() },
                onPlayPrevious: { onPlayPrevious?() },
                onToggleMute: {
                    wakeUpControls()
                    let newVolume = volume > 0 ? 0.0 : 1.0
                    player?.volume = Float(newVolume)
                },
                onToggleFullScreen: { wakeUpControls(); onToggleFullScreen?() },
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
                        seek(to: draggingSeconds)
                    }
                },
                onSetPlaybackRate: { r in
                    wakeUpControls()
                    setPlaybackRate(r)
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
                        seek(to: Double(skipIntroSeconds))
                    }
                },
                onSkipOutro: {
                    if skipOutroSeconds > 0, duration > 0 {
                        seek(to: duration - Double(skipOutroSeconds))
                    }
                },
                onShowSettings: {
                    showSettingsSheet = true
                },
                onBack: { onBack?() },
                onSetVideoFit: { videoFitType = $0 },
                onTogglePiP: { pipManager.togglePiP() },
                onCast: {}
            )
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
        .sheet(isPresented: $showSettingsSheet) {
            PlayerSettingsSheet(
                currentPlaybackEngine: .system,
                skipIntroSeconds: skipIntroSeconds,
                skipOutroSeconds: skipOutroSeconds,
                playbackRate: rate,
                currentResolution: networkMonitor.resolutionText,
                currentBitrate: networkMonitor.bitrateText,
                videoFitType: videoFitType,
                onSwitchPlayer: { onSwitchPlayer?() },
                onSetPlaybackRate: { r in setPlaybackRate(r) },
                onSetSkipIntro: { skipIntroSeconds = $0 },
                onSetSkipOutro: { skipOutroSeconds = $0 },
                onSetVideoFit: { videoFitType = $0 },
                onShowPlayerInfo: {}
            )
        }
        .onAppear {
            setupGestureCallbacks()
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
            pipManager.teardown()
            networkMonitor.detach()
            cleanupPlayer(keepSharedPlayer: sharedController != nil)
            controlsTimer?.invalidate()
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
                        seek(by: -seekStep)
                        gestureDelegate.showBackwardSeek = false
                    }
                }
            case .center:
                togglePlayPause()
            case .right:
                gestureDelegate.showForwardSeek = true
                gestureDelegate.seekAccumulatedSeconds = Int(seekStep)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if gestureDelegate.showForwardSeek {
                        seek(by: seekStep)
                        gestureDelegate.showForwardSeek = false
                    }
                }
            }
        }

        gestureDelegate.onLongPressStart = {
            savedPlaybackRateBeforeLongPress = rate
            gestureDelegate.longPressSpeed = rate * 2
            setPlaybackRate(rate * 2)
            gestureDelegate.showLongPressIndicator = true
        }

        gestureDelegate.onLongPressEnd = {
            setPlaybackRate(savedPlaybackRateBeforeLongPress)
            gestureDelegate.showLongPressIndicator = false
        }

        gestureDelegate.onHorizontalSeek = { delta in
            let scale = duration > 0 ? duration * 0.3 : 300
            let seekDelta = Double(delta) / UIScreen.main.bounds.width * scale
            sliderTempPosition = max(0, sliderTempPosition + seekDelta)
            if duration > 0 {
                sliderTempPosition = min(sliderTempPosition, duration)
            }
            draggingSeconds = sliderTempPosition
            isDraggingProgress = true
        }

        gestureDelegate.onVolumeChange = { newVolume in
            player?.volume = Float(newVolume)
        }

        gestureDelegate.onFullScreenGesture = { enterFullScreen in
            onToggleFullScreen?()
        }

        gestureDelegate.onGestureEnd = {
            if isDraggingProgress {
                seek(to: draggingSeconds)
                isDraggingProgress = false
            }
        }
    }
    #else
    private func setupGestureCallbacks() {}
    #endif

    private func hideControls() {
        withAnimation(.easeOut(duration: 0.3)) {
            showControls = false
        }
        controlsTimer?.invalidate()
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

        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        if #available(iOS 17.0, *) {
            newPlayer.defaultRate = preferredRate
        }
        if let sharedController {
            sharedController.setPlayer(newPlayer, urlString: targetURLString)
        }

        player = newPlayer
        bindPlayerObservers(for: newPlayer)
        startPlayback(for: newPlayer)
    }

    private func bindPlayerObservers(for player: AVPlayer) {
        let observers = [
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
        }
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
