import SwiftUI
import Combine
import AVFoundation

#if os(iOS)
import UIKit
import AVKit
#endif

enum VideoFitType: Int, CaseIterable {
    case fill = 0
    case contain = 1
    case cover = 2
    case fitWidth = 3
    case fitHeight = 4
    case none = 5
    case ratio4x3 = 6
    case ratio16x9 = 7

    var desc: String {
        switch self {
        case .fill: return "拉伸"
        case .contain: return "自动"
        case .cover: return "裁剪"
        case .fitWidth: return "等宽"
        case .fitHeight: return "等高"
        case .none: return "原始"
        case .ratio4x3: return "4:3"
        case .ratio16x9: return "16:9"
        }
    }

    var contentMode: ContentMode {
        switch self {
        case .fill, .cover: return .fill
        default: return .fit
        }
    }

    var avVideoGravity: AVLayerVideoGravity {
        switch self {
        case .fill: return .resize
        case .contain: return .resizeAspect
        case .cover: return .resizeAspectFill
        case .fitWidth: return .resizeAspect
        case .fitHeight: return .resizeAspect
        case .none: return .resizeAspect
        case .ratio4x3: return .resizeAspect
        case .ratio16x9: return .resizeAspect
        }
    }

    #if os(iOS)
    var uiContentMode: UIView.ContentMode {
        switch self {
        case .fill: return .scaleToFill
        case .contain: return .scaleAspectFit
        case .cover: return .scaleAspectFill
        case .fitWidth: return .scaleAspectFit
        case .fitHeight: return .scaleAspectFit
        case .none: return .center
        case .ratio4x3: return .scaleAspectFit
        case .ratio16x9: return .scaleAspectFit
        }
    }
    #endif

    var aspectRatio: CGFloat? {
        switch self {
        case .ratio4x3: return 4.0 / 3.0
        case .ratio16x9: return 16.0 / 9.0
        default: return nil
        }
    }
}

@MainActor
final class PlayerNetworkMonitor: ObservableObject {
    @Published var bitrateText: String = ""
    @Published var resolutionText: String = ""

    private var player: AVPlayer?
    private var accessLogTimer: Timer?
    private var trackObserver: NSKeyValueObservation?

    func attach(to player: AVPlayer) {
        self.player = player
        startMonitoring()
        observeTracks()
    }

    func detach() {
        stopMonitoring()
        trackObserver?.invalidate()
        trackObserver = nil
        player = nil
    }

    private func observeTracks() {
        guard let player = player else { return }
        trackObserver = player.currentItem?.observe(\.tracks, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.updateResolution(from: item)
            }
        }
        updateResolution(from: player.currentItem)
    }

    private func updateResolution(from item: AVPlayerItem?) {
        guard let item = item else { return }
        var width: Int = 0
        var height: Int = 0
        for track in item.tracks {
            if let size = track.assetTrack?.naturalSize, size.width > 0, size.height > 0 {
                width = Int(size.width)
                height = Int(size.height)
                break
            }
        }
        if width > 0, height > 0 {
            resolutionText = "\(width)×\(height)"
        }
    }

    private func startMonitoring() {
        accessLogTimer?.invalidate()
        accessLogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateBitrate()
            }
        }
    }

    private func stopMonitoring() {
        accessLogTimer?.invalidate()
        accessLogTimer = nil
    }

    private func updateBitrate() {
        guard let item = player?.currentItem,
              let log = item.accessLog(),
              let event = log.events.last else {
            bitrateText = ""
            return
        }
        let bitrate = event.indicatedBitrate
        if bitrate > 0 {
            let mbps = bitrate / 1_000_000.0
            if mbps >= 1.0 {
                bitrateText = String(format: "%.1fMbps", mbps)
            } else {
                let kbps = bitrate / 1_000.0
                bitrateText = String(format: "%.0fKbps", kbps)
            }
        } else {
            let observedBitrate = event.observedBitrate
            if observedBitrate > 0 {
                let mbps = observedBitrate / 1_000_000.0
                if mbps >= 1.0 {
                    bitrateText = String(format: "%.1fMbps", mbps)
                } else {
                    let kbps = observedBitrate / 1_000.0
                    bitrateText = String(format: "%.0fKbps", kbps)
                }
            } else {
                bitrateText = ""
            }
        }
        if resolutionText.isEmpty {
            updateResolution(from: item)
        }
    }
}

struct PlayerControlsOverlay: View {
    let isPlaying: Bool
    let isPreparing: Bool
    let currentTime: Double
    let duration: Double
    let hasValidDuration: Bool
    let isDraggingProgress: Bool
    let draggingSeconds: Double
    let playbackRate: Float
    let isFullScreen: Bool
    let isLocked: Bool
    let canPlayNext: Bool
    let canPlayPrevious: Bool
    let showControls: Bool
    let volumeIconName: String
    let seekStep: Double
    let videoTitle: String
    let currentEpisodeName: String
    let currentResolution: String
    let currentBitrate: String
    let showEpisodeButton: Bool
    let showPlayerSwitchButton: Bool
    let skipIntroSeconds: Int
    let skipOutroSeconds: Int
    let currentPlaybackEngine: PlayerEngine
    let videoFitType: VideoFitType
    let episodeNames: [String]
    let selectedEpisodeIndex: Int

    let onTogglePlayPause: () -> Void
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void
    let onPlayNext: () -> Void
    let onPlayPrevious: () -> Void
    let onToggleMute: () -> Void
    let onToggleFullScreen: () -> Void
    let onProgressDragChanged: (Double) -> Void
    let onProgressDragEnded: (Bool) -> Void
    let onSetPlaybackRate: (Float) -> Void
    let onToggleLock: () -> Void
    let onWakeUpControls: () -> Void
    let onShowEpisodes: () -> Void
    let onSelectEpisode: (Int) -> Void
    let onSwitchPlayer: () -> Void
    let onSkipIntro: () -> Void
    let onSkipOutro: () -> Void
    let onShowSettings: () -> Void
    let onBack: () -> Void
    let onSetVideoFit: (VideoFitType) -> Void
    let onTogglePiP: () -> Void
    let onCast: () -> Void

    private static let supportedPlaybackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    @State private var currentClockTime: String = ""
    @State private var clockTimer: Timer?
    @State private var batteryLevel: Int = -1
    @State private var showSkipIntro: Bool = false
    @State private var showSkipOutro: Bool = false
    @State private var showEpisodeSheet = false

    private var progressUpperBound: Double {
        max(duration, max(currentTime, 1))
    }

    private var displayCurrentTime: String {
        (isDraggingProgress ? draggingSeconds : currentTime).durationString
    }

    private var displayDuration: String {
        hasValidDuration ? duration.durationString : "--:--"
    }

    private var displayTitle: String {
        if currentEpisodeName.isEmpty {
            return videoTitle
        }
        return "\(videoTitle) - \(currentEpisodeName)"
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if showControls && !isLocked {
                    headerBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                if showControls || isLocked {
                    lockButton
                        .transition(.opacity)
                }

                if showControls && !isLocked {
                    bottomSection
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if !isLocked {
                skipButtons
            }

            if showEpisodeSheet {
                episodeOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showControls)
        .animation(.easeInOut(duration: 0.25), value: showEpisodeSheet)
        .animation(.easeInOut(duration: 0.25), value: isLocked)
        .onAppear {
            startClock()
            updateSkipButtons()
        }
        .onDisappear {
            clockTimer?.invalidate()
        }
        .onChange(of: currentTime) { _ in
            updateSkipButtons()
        }
    }

    private func startClock() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        currentClockTime = formatter.string(from: Date())
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                currentClockTime = formatter.string(from: Date())
            }
        }
        #if os(iOS)
        Task {
            if let level = try? await getBatteryLevel() {
                batteryLevel = level
            }
        }
        #endif
    }

    #if os(iOS)
    private func getBatteryLevel() async throws -> Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = Int(UIDevice.current.batteryLevel * 100)
        UIDevice.current.isBatteryMonitoringEnabled = false
        return level
    }
    #endif

    private func updateSkipButtons() {
        if skipIntroSeconds > 0, currentTime > 0, currentTime < Double(skipIntroSeconds) {
            showSkipIntro = true
        } else {
            showSkipIntro = false
        }
        if skipOutroSeconds > 0, duration > 0, currentTime > duration - Double(skipOutroSeconds) {
            showSkipOutro = true
        } else {
            showSkipOutro = false
        }
    }

    // MARK: - Header Bar (PiliPlus style)

    private var headerBar: some View {
        HStack(spacing: 0) {
            comBtn(
                icon: Image(systemName: "chevron.left"),
                size: 15,
                width: 40,
                height: 34,
                action: onBack
            )

            if !displayTitle.isEmpty {
                Text(displayTitle)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.trailing, 10)
            }

            Spacer()

            if !currentResolution.isEmpty {
                Text(currentResolution)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.trailing, 4)
            }

            if !currentBitrate.isEmpty {
                Text(currentBitrate)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.trailing, 4)
            }

            if isFullScreen && !currentClockTime.isEmpty {
                if batteryLevel >= 0 {
                    Text("\(batteryLevel)%")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .padding(.trailing, 10)
                }
                Text(currentClockTime)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
            }

            #if os(iOS)
            AirPlayPickerButton()
                .frame(width: 40, height: 34)
            #endif

            #if os(iOS)
            if currentPlaybackEngine == .system {
                comBtn(
                    icon: Image(systemName: "pip.enter"),
                    size: 19,
                    width: 40,
                    height: 34,
                    action: { onWakeUpControls(); onTogglePiP() }
                )
            }
            #endif

            comBtn(
                icon: Image(systemName: "ellipsis"),
                size: 19,
                width: 40,
                height: 34,
                action: { onWakeUpControls(); onShowSettings() }
            )
        }
        .padding(.top, 11)
        .padding(.horizontal, 4)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Lock Button

    private var lockButton: some View {
        GeometryReader { geo in
            Button {
                onToggleLock()
            } label: {
                Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .position(x: 30, y: geo.size.height / 2)
        }
    }

    // MARK: - Bottom Section (PiliPlus style: progress bar + control bar)

    private var bottomSection: some View {
        VStack(spacing: 0) {
            progressBarArea
                .padding(.horizontal, 20)

            controlBar
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Skip Buttons

    private var skipButtons: some View {
        HStack(spacing: 12) {
            if showSkipIntro {
                Button {
                    onSkipIntro()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 11))
                        Text("跳过片头")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            Spacer()

            if showSkipOutro {
                Button {
                    onSkipOutro()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 11))
                        Text("跳过片尾")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 16)
        .offset(y: -6)
        .animation(.easeInOut(duration: 0.2), value: showSkipIntro)
        .animation(.easeInOut(duration: 0.2), value: showSkipOutro)
    }

    // MARK: - Progress Bar (PiliPlus style: thin bar, no time labels)

    private var progressBarArea: some View {
        PlayerProgressBar(
            value: Binding(
                get: { isDraggingProgress ? draggingSeconds : currentTime },
                set: { onProgressDragChanged($0) }
            ),
            in: 0...progressUpperBound,
            onEditingChanged: { editing in
                onProgressDragEnded(editing)
            }
        )
        .tint(.white)
        .padding(.horizontal, 10)
        .frame(height: 20)
    }

    // MARK: - Control Bar (PiliPlus style: left segment + right segment)

    private var controlBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                playPauseBtn

                videoTimeView

                if canPlayPrevious {
                    comBtn(
                        icon: Image(systemName: "backward.end.fill"),
                        size: 22,
                        width: 35,
                        height: 30,
                        action: { onWakeUpControls(); onPlayPrevious() }
                    )
                }

                if canPlayNext {
                    comBtn(
                        icon: Image(systemName: "forward.end.fill"),
                        size: 22,
                        width: 35,
                        height: 30,
                        action: { onWakeUpControls(); onPlayNext() }
                    )
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                if showEpisodeButton {
                    comBtn(
                        icon: Image(systemName: "list.bullet"),
                        size: 22,
                        width: 35,
                        height: 30,
                        action: { onWakeUpControls(); showEpisodeSheet = true }
                    )
                }

                videoFitMenu

                playbackRateMenu

                if showPlayerSwitchButton {
                    playerSwitchBtn
                }

                comBtn(
                    icon: Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"),
                    size: 24,
                    width: 42,
                    height: 30,
                    action: { onWakeUpControls(); onToggleFullScreen() }
                )
            }
        }
    }

    // MARK: - Play/Pause Button (PiliPlus style: 42x34, AnimatedIcon)

    private var playPauseBtn: some View {
        Button(action: onTogglePlayPause) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 42, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Video Time (PiliPlus style: monospace, position white + duration gray)

    private var videoTimeView: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(displayCurrentTime)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.white)

            Text(displayDuration)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(Color(red: 0.82, green: 0.82, blue: 0.82))
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Playback Rate Menu (PiliPlus style: text label "1.0X")

    private var playbackRateMenu: some View {
        Menu {
            ForEach(Self.supportedPlaybackRates, id: \.self) { r in
                Button {
                    onWakeUpControls()
                    onSetPlaybackRate(r)
                } label: {
                    HStack {
                        Text("\(String(format: "%.1f", r))X")
                        if abs(r - playbackRate) < 0.01 {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text("\(String(format: "%.1f", playbackRate))X")
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Video Fit Menu (PiliPlus style: text label "自动"/"16:9")

    private var videoFitMenu: some View {
        Menu {
            ForEach(VideoFitType.allCases, id: \.self) { fit in
                Button {
                    onWakeUpControls()
                    onSetVideoFit(fit)
                } label: {
                    HStack {
                        Text(fit.desc)
                        if fit == videoFitType {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(videoFitType.desc)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Player Switch Menu

    @State private var showPlayerSwitchAlert = false

    private var playerSwitchBtn: some View {
        Button {
            onWakeUpControls()
            showPlayerSwitchAlert = true
        } label: {
            Text("播放器")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .confirmationDialog("选择播放器", isPresented: $showPlayerSwitchAlert, titleVisibility: .visible) {
            Button(currentPlaybackEngine == .vlc ? "VLC ✓" : "VLC") {
                if currentPlaybackEngine != .vlc {
                    onSwitchPlayer()
                }
            }
            Button(currentPlaybackEngine == .system ? "系统 ✓" : "系统") {
                if currentPlaybackEngine != .system {
                    onSwitchPlayer()
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Episode Overlay

    private var episodeOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { showEpisodeSheet = false }

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    HStack {
                        Text("选集")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            showEpisodeSheet = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 8)
                        ], spacing: 8) {
                            ForEach(Array(episodeNames.enumerated()), id: \.offset) { index, name in
                                Button {
                                    onSelectEpisode(index)
                                    showEpisodeSheet = false
                                } label: {
                                    Text(name)
                                        .font(.system(size: 13))
                                        .foregroundColor(index == selectedEpisodeIndex ? .white : .white.opacity(0.7))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .frame(minWidth: 80)
                                        .background(
                                            index == selectedEpisodeIndex
                                                ? Color.white.opacity(0.25)
                                                : Color.white.opacity(0.08)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .frame(maxHeight: 300)
                }
                .background(Color(red: 0.12, green: 0.12, blue: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Common Button (PiliPlus ComBtn style)

    private func comBtn(
        icon: Image,
        size: CGFloat,
        width: CGFloat = 34,
        height: CGFloat = 34,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon
                .font(.system(size: size))
                .foregroundColor(.white)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress Bar (PiliPlus style: 3.5px track, 7px thumb)

struct PlayerProgressBar: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    init(value: Binding<Double>, in range: ClosedRange<Double>, onEditingChanged: @escaping (Bool) -> Void) {
        self._value = value
        self.range = range
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let upperBound = range.upperBound - range.lowerBound
            let progress = upperBound > 0 ? (dragValue - range.lowerBound) / upperBound : 0
            let thumbRadius: CGFloat = 7
            let trackHeight: CGFloat = 3.5

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: trackHeight)
                    .clipShape(Capsule())

                Rectangle()
                    .fill(Color.white)
                    .frame(width: max(0, CGFloat(progress) * totalWidth), height: trackHeight)
                    .clipShape(Capsule())

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .shadow(color: .white.opacity(0.3), radius: thumbRadius, x: 0, y: 0)
                    .position(
                        x: max(thumbRadius, min(totalWidth - thumbRadius, CGFloat(progress) * totalWidth)),
                        y: geometry.size.height / 2
                    )
            }
            .frame(height: thumbRadius * 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragValue in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let newValue = range.lowerBound + Double(dragValue.location.x / totalWidth) * (range.upperBound - range.lowerBound)
                        self.dragValue = min(max(newValue, range.lowerBound), range.upperBound)
                        self.value = self.dragValue
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 20)
        .onChange(of: value) { newValue in
            if !isDragging {
                dragValue = newValue
            }
        }
        .onAppear {
            dragValue = value
        }
    }
}

// MARK: - Settings Sheet

struct PlayerSettingsSheet: View {
    let currentPlaybackEngine: PlayerEngine
    let skipIntroSeconds: Int
    let skipOutroSeconds: Int
    let playbackRate: Float
    let currentResolution: String
    let currentBitrate: String
    let videoFitType: VideoFitType

    let onSwitchPlayer: () -> Void
    let onSetPlaybackRate: (Float) -> Void
    let onSetSkipIntro: (Int) -> Void
    let onSetSkipOutro: (Int) -> Void
    let onSetVideoFit: (VideoFitType) -> Void
    let onShowPlayerInfo: () -> Void

    @Environment(\.dismiss) private var dismiss

    private static let supportedPlaybackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
    private static let skipOptions: [Int] = [0, 30, 60, 90, 120, 180]

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("播放器")) {
                    HStack {
                        Text("当前播放器")
                        Spacer()
                        Text(currentPlaybackEngine == .vlc ? "VLC" : "系统")
                            .foregroundColor(.secondary)
                    }
                    Button {
                        onSwitchPlayer()
                        dismiss()
                    } label: {
                        HStack {
                            Text("切换播放器")
                            Spacer()
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("倍速")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.supportedPlaybackRates, id: \.self) { r in
                                Button {
                                    onSetPlaybackRate(r)
                                } label: {
                                    Text("\(String(format: "%.1f", r))x")
                                        .font(.system(size: 13, weight: abs(r - playbackRate) < 0.01 ? .bold : .regular, design: .monospaced))
                                        .foregroundColor(abs(r - playbackRate) < 0.01 ? .white : .primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(abs(r - playbackRate) < 0.01 ? Color.accentColor : Color(.systemGray5))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text("画面比例")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(VideoFitType.allCases, id: \.self) { fit in
                                Button {
                                    onSetVideoFit(fit)
                                } label: {
                                    Text(fit.desc)
                                        .font(.system(size: 13, weight: fit == videoFitType ? .bold : .regular))
                                        .foregroundColor(fit == videoFitType ? .white : .primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(fit == videoFitType ? Color.accentColor : Color(.systemGray5))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text("跳过")) {
                    HStack {
                        Text("跳过片头")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { skipIntroSeconds },
                            set: { onSetSkipIntro($0) }
                        )) {
                            ForEach(Self.skipOptions, id: \.self) { s in
                                Text(s == 0 ? "关闭" : "\(s)秒").tag(s)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("跳过片尾")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { skipOutroSeconds },
                            set: { onSetSkipOutro($0) }
                        )) {
                            ForEach(Self.skipOptions, id: \.self) { s in
                                Text(s == 0 ? "关闭" : "\(s)秒").tag(s)
                            }
                        }
                        .labelsHidden()
                    }
                }

                Section(header: Text("播放信息")) {
                    if !currentResolution.isEmpty {
                        HStack {
                            Text("分辨率")
                            Spacer()
                            Text(currentResolution)
                                .foregroundColor(.secondary)
                        }
                    }
                    if !currentBitrate.isEmpty {
                        HStack {
                            Text("网速")
                            Spacer()
                            Text(currentBitrate)
                                .foregroundColor(.secondary)
                        }
                    }
                    Button {
                        onShowPlayerInfo()
                    } label: {
                        Text("详细播放信息")
                    }
                }
            }
            .navigationTitle("播放设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - AirPlay Picker

#if os(iOS)
struct AirPlayPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .white
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

// MARK: - PiP Manager

@MainActor
final class PlayerPiPManager: NSObject, ObservableObject {
    @Published var isPiPSupported = false
    @Published var isPiPActive = false

    #if os(iOS)
    private var pipController: AVPictureInPictureController?
    private var pipPossibleObservation: NSKeyValueObservation?
    #endif

    #if os(iOS)
    func setup(with playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if let existing = pipController, existing.playerLayer === playerLayer { return }

        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self

        pipPossibleObservation = pipController?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] controller, _ in
            Task { @MainActor in
                self?.isPiPSupported = controller.isPictureInPicturePossible
            }
        }
    }
    #endif

    func teardown() {
        #if os(iOS)
        pipPossibleObservation?.invalidate()
        pipPossibleObservation = nil
        pipController?.delegate = nil
        pipController = nil
        #endif
        isPiPSupported = false
        isPiPActive = false
    }

    func togglePiP() {
        #if os(iOS)
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
        #endif
    }
}

#if os(iOS)
extension PlayerPiPManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = false
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            isPiPActive = false
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
#endif
