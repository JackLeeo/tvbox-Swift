import SwiftUI

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

    private static let supportedPlaybackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

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
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Spacer()
        }
        .padding(.horizontal, 16)
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
            HStack(spacing: 16) {
                playbackRateMenu
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

            HStack(spacing: 16) {
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
                    icon: "arrow.up.left.and.arrow.down.right",
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
