import SwiftUI
import Combine

#if os(iOS)
import UIKit
#endif

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

    let onTogglePlayPause: () -> Void
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void
    let onPlayNext: () -> Void
    let onToggleMute: () -> Void
    let onToggleFullScreen: () -> Void
    let onProgressDragChanged: (Double) -> Void
    let onProgressDragEnded: (Bool) -> Void
    let onSetPlaybackRate: (Float) -> Void
    let onToggleLock: () -> Void
    let onWakeUpControls: () -> Void
    let onShowEpisodes: () -> Void
    let onSwitchPlayer: () -> Void
    let onSkipIntro: () -> Void
    let onSkipOutro: () -> Void
    let onShowSettings: () -> Void
    let onBack: () -> Void

    private static let supportedPlaybackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    @State private var currentClockTime: String = ""
    @State private var clockTimer: Timer?
    @State private var batteryLevel: Int = -1
    @State private var showSkipIntro: Bool = false
    @State private var showSkipOutro: Bool = false

    private var progressUpperBound: Double {
        max(duration, max(currentTime, 1))
    }

    private var displayCurrentTime: String {
        (isDraggingProgress ? draggingSeconds : currentTime).durationString
    }

    private var displayDuration: String {
        hasValidDuration ? duration.durationString : "--:--"
    }

    private var seekBackwardIcon: String {
        let step = Int(seekStep)
        let validSteps = [5, 10, 15, 30, 60, 90, 120]
        return validSteps.contains(step) ? "gobackward.\(step)" : "gobackward.10"
    }

    private var seekForwardIcon: String {
        let step = Int(seekStep)
        let validSteps = [5, 10, 15, 30, 60, 90, 120]
        return validSteps.contains(step) ? "goforward.\(step)" : "goforward.10"
    }

    private var displayTitle: String {
        if currentEpisodeName.isEmpty {
            return videoTitle
        }
        return "\(videoTitle) - \(currentEpisodeName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if showControls && !isLocked {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            if isLocked && showControls {
                lockButton
                    .transition(.opacity)
            }

            if showControls && !isLocked {
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showControls)
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

    private var topBar: some View {
        HStack(spacing: 8) {
            if isFullScreen {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)
            }

            if isFullScreen && !displayTitle.isEmpty {
                Text(displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }

            Spacer()

            if !currentResolution.isEmpty {
                Text(currentResolution)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if !currentBitrate.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "network")
                        .font(.system(size: 10))
                    Text(currentBitrate)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if isFullScreen && !currentClockTime.isEmpty {
                Text(currentClockTime)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }

            #if os(iOS)
            if isFullScreen && batteryLevel >= 0 {
                HStack(spacing: 3) {
                    batteryIcon
                        .font(.system(size: 12))
                    Text("\(batteryLevel)%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.8))
            }
            #endif

            Button {
                onWakeUpControls()
                onShowSettings()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    #if os(iOS)
    private var batteryIcon: Image {
        let level = batteryLevel
        let iconName: String
        if level <= 0 {
            iconName = "battery.0"
        } else if level < 25 {
            iconName = "battery.25"
        } else if level < 50 {
            iconName = "battery.50"
        } else if level < 75 {
            iconName = "battery.75"
        } else {
            iconName = "battery.100"
        }
        return Image(systemName: iconName)
    }
    #endif

    private var lockButton: some View {
        HStack {
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
            Spacer()
        }
        .padding(.leading, 20)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            progressBarArea
                .padding(.horizontal, 16)

            controlButtonsArea
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
        .overlay(alignment: .topLeading) {
            skipButtons
        }
    }

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

    private var progressBarArea: some View {
        HStack(spacing: 12) {
            Text(displayCurrentTime)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 50, alignment: .leading)

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

            Text(displayDuration)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 50, alignment: .trailing)
        }
    }

    private var controlButtonsArea: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                playbackRateMenu

                if showPlayerSwitchButton {
                    playerSwitchMenu
                }
            }

            Spacer()

            HStack(spacing: 28) {
                controlButton(
                    icon: seekBackwardIcon,
                    size: 20,
                    action: { onWakeUpControls(); onSeekBackward() }
                )

                controlButton(
                    icon: isPlaying ? "pause.fill" : "play.fill",
                    size: 28,
                    weight: .medium,
                    action: onTogglePlayPause
                )

                controlButton(
                    icon: seekForwardIcon,
                    size: 20,
                    action: { onWakeUpControls(); onSeekForward() }
                )

                if canPlayNext {
                    controlButton(
                        icon: "forward.end.fill",
                        size: 20,
                        opacity: canPlayNext ? 1 : 0.4,
                        action: { onWakeUpControls(); onPlayNext() }
                    )
                }
            }

            Spacer()

            HStack(spacing: 14) {
                if showEpisodeButton {
                    controlButton(
                        icon: "list.bullet",
                        size: 16,
                        action: { onWakeUpControls(); onShowEpisodes() }
                    )
                }

                controlButton(
                    icon: volumeIconName,
                    size: 16,
                    action: { onWakeUpControls(); onToggleMute() }
                )

                if isFullScreen {
                    controlButton(
                        icon: isLocked ? "lock.fill" : "lock.open.fill",
                        size: 16,
                        action: { onWakeUpControls(); onToggleLock() }
                    )
                }

                controlButton(
                    icon: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    size: 17,
                    weight: .semibold,
                    action: { onWakeUpControls(); onToggleFullScreen() }
                )
            }
        }
    }

    private func controlButton(
        icon: String,
        size: CGFloat,
        weight: Font.Weight = .regular,
        opacity: Double = 1.0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: weight))
                .foregroundColor(.white)
                .opacity(opacity)
        }
        .buttonStyle(.plain)
    }

    private var playbackRateMenu: some View {
        Menu {
            ForEach(Self.supportedPlaybackRates, id: \.self) { r in
                Button {
                    onWakeUpControls()
                    onSetPlaybackRate(r)
                } label: {
                    HStack {
                        Text("\(String(format: "%.1f", r))x")
                        if abs(r - playbackRate) < 0.01 {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(String(format: "%.1f", playbackRate))x")
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

    private var playerSwitchMenu: some View {
        Menu {
            Button {
                onWakeUpControls()
                onSwitchPlayer()
            } label: {
                HStack {
                    Text(currentPlaybackEngine == .vlc ? "系统播放器" : "VLC播放器")
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

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
            let trackHeight: CGFloat = 3

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: trackHeight)
                    .clipShape(Capsule())

                Rectangle()
                    .fill(Color.white)
                    .frame(width: max(0, CGFloat(progress) * totalWidth), height: trackHeight)
                    .clipShape(Capsule())

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
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

struct PlayerSettingsSheet: View {
    let currentPlaybackEngine: PlayerEngine
    let skipIntroSeconds: Int
    let skipOutroSeconds: Int
    let playbackRate: Float
    let currentResolution: String
    let currentBitrate: String

    let onSwitchPlayer: () -> Void
    let onSetPlaybackRate: (Float) -> Void
    let onSetSkipIntro: (Int) -> Void
    let onSetSkipOutro: (Int) -> Void
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
