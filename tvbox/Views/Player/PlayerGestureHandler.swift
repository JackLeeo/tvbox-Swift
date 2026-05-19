import SwiftUI
import Darwin

#if os(iOS)
import UIKit
import AVFoundation

enum PlayerGestureType {
    case none
    case horizontal
    case leftVertical
    case centerVertical
    case rightVertical
}

enum PlayerDoubleTapZone {
    case left
    case center
    case right
}

@MainActor
final class PlayerGestureDelegate: ObservableObject {
    var isLive: Bool = false
    var isLocked: Bool = false
    var enableQuickDouble: Bool = true
    var fastForBackwardDuration: Int = 10

    var onToggleControls: (() -> Void)?
    var onDoubleTap: ((PlayerDoubleTapZone) -> Void)?
    var onLongPressStart: (() -> Void)?
    var onLongPressEnd: (() -> Void)?
    var onHorizontalSeek: ((CGFloat) -> Void)?
    var onBrightnessChange: ((CGFloat) -> Void)?
    var onVolumeChange: ((CGFloat) -> Void)?
    var onFullScreenGesture: ((Bool) -> Void)?
    var onGestureEnd: (() -> Void)?

    @Published var showBrightnessIndicator: Bool = false
    @Published var brightnessValue: Double = 0.5
    @Published var showVolumeIndicator: Bool = false
    @Published var volumeValue: Double = 0.5
    @Published var showLongPressIndicator: Bool = false
    @Published var longPressSpeed: Float = 2.0
    @Published var showForwardSeek: Bool = false
    @Published var showBackwardSeek: Bool = false
    @Published var seekAccumulatedSeconds: Int = 0

    private var gestureType: PlayerGestureType = .none
    private var initialLocation: CGPoint = .zero
    private var initialBrightness: CGFloat = 0
    private var initialVolume: CGFloat = 0
    private var lastHorizontalTranslation: CGFloat = 0
    private var longPressActive: Bool = false
    private var brightnessTimer: Timer?
    private var volumeTimer: Timer?
    private var seekSubmitTimer: Timer?
    private var viewWidth: CGFloat = 0

    func setViewWidth(_ width: CGFloat) {
        viewWidth = width
    }

    func handleSingleTap(at location: CGPoint) {
        onToggleControls?()
    }

    func handleDoubleTap(at location: CGPoint) {
        guard !isLocked else { return }

        if !enableQuickDouble {
            onDoubleTap?(.center)
            return
        }

        let zone: PlayerDoubleTapZone
        if viewWidth > 0 {
            if location.x < viewWidth / 4 {
                zone = .left
            } else if location.x < viewWidth * 3 / 4 {
                zone = .center
            } else {
                zone = .right
            }
        } else {
            zone = .center
        }
        onDoubleTap?(zone)
    }

    func handleLongPressStart() {
        guard !isLive, !isLocked else { return }
        longPressActive = true
        onLongPressStart?()
    }

    func handleLongPressEnd() {
        guard longPressActive else { return }
        longPressActive = false
        onLongPressEnd?()
    }

    func handlePanStart(at location: CGPoint, viewWidth: CGFloat) {
        self.viewWidth = viewWidth
        gestureType = .none
        initialLocation = location
        lastHorizontalTranslation = 0
        initialBrightness = CGFloat(UIScreen.main.brightness)
        initialVolume = 0.5
    }

    func handlePanUpdate(translation: CGSize) {
        if longPressActive { return }
        if isLocked { return }

        if gestureType == .none {
            let dx = abs(translation.width)
            let dy = abs(translation.height)
            if dx < 8 && dy < 8 { return }

            if dx > dy * 1.5 {
                if isLive { return }
                gestureType = .horizontal
            } else if dy > dx * 1.5 {
                let screenWidth = viewWidth > 0 ? viewWidth : UIScreen.main.bounds.width
                let relativeX = initialLocation.x
                if relativeX < screenWidth / 3 {
                    gestureType = .leftVertical
                } else if relativeX < screenWidth * 2 / 3 {
                    gestureType = .centerVertical
                } else {
                    gestureType = .rightVertical
                }
            }
            return
        }

        switch gestureType {
        case .horizontal:
            let totalDelta = translation.width
            let delta = totalDelta - lastHorizontalTranslation
            lastHorizontalTranslation = totalDelta
            onHorizontalSeek?(delta)
        case .leftVertical:
            let level = UIScreen.main.bounds.height * 3
            let newBrightness = (initialBrightness - translation.height / level).clamped(to: 0...1)
            brightnessValue = Double(newBrightness)
            showBrightnessIndicator = true
            brightnessTimer?.invalidate()
            brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                Task { @MainActor in
                    self.showBrightnessIndicator = false
                }
            }
            UIScreen.main.brightness = newBrightness
            onBrightnessChange?(newBrightness)
        case .rightVertical:
            let level = UIScreen.main.bounds.height * 0.5
            let delta = -translation.height / level
            let newVolume = (volumeValue + delta).clamped(to: 0...1)
            volumeValue = newVolume
            showVolumeIndicator = true
            volumeTimer?.invalidate()
            volumeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                Task { @MainActor in
                    self.showVolumeIndicator = false
                }
            }
            onVolumeChange?(newVolume)
        case .centerVertical:
            let threshold: CGFloat = 50
            if translation.height > threshold {
                onFullScreenGesture?(false)
            } else if translation.height < -threshold {
                onFullScreenGesture?(true)
            }
        default:
            break
        }
    }

    func handlePanEnd() {
        if longPressActive {
            longPressActive = false
            onLongPressEnd?()
        }
        if gestureType != .none {
            onGestureEnd?()
        }
        gestureType = .none
        lastHorizontalTranslation = 0
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

struct PlayerGestureOverlay: UIViewRepresentable {
    @ObservedObject var delegate: PlayerGestureDelegate

    func makeUIView(context: Context) -> PlayerGestureUIView {
        let view = PlayerGestureUIView()
        view.gestureDelegate = delegate
        view.setupGestures()
        return view
    }

    func updateUIView(_ uiView: PlayerGestureUIView, context: Context) {
        uiView.gestureDelegate = delegate
    }
}

final class PlayerGestureUIView: UIView {
    weak var gestureDelegate: PlayerGestureDelegate?

    private var tapGesture: UITapGestureRecognizer!
    private var doubleTapGesture: UITapGestureRecognizer!
    private var longPressGesture: UILongPressGestureRecognizer!
    private var panGesture: UIPanGestureRecognizer!

    func setupGestures() {
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1

        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2

        tapGesture.require(toFail: doubleTapGesture)

        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1

        addGestureRecognizer(tapGesture)
        addGestureRecognizer(doubleTapGesture)
        addGestureRecognizer(longPressGesture)
        addGestureRecognizer(panGesture)

        let simultaneous: [(UIGestureRecognizer, UIGestureRecognizer)] = [
            (panGesture, tapGesture),
            (panGesture, doubleTapGesture),
            (panGesture, longPressGesture),
        ]
        for (a, b) in simultaneous {
            a.shouldRequireFailure(of: b)
            b.shouldRequireFailure(of: a)
        }
        panGesture.shouldRequireFailure(of: longPressGesture)

        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        gestureDelegate?.handleSingleTap(at: location)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        gestureDelegate?.handleDoubleTap(at: location)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            gestureDelegate?.handleLongPressStart()
        case .ended, .cancelled:
            gestureDelegate?.handleLongPressEnd()
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .began:
            gestureDelegate?.handlePanStart(at: location, viewWidth: bounds.width)
        case .changed:
            gestureDelegate?.handlePanUpdate(translation: translation)
        case .ended, .cancelled:
            gestureDelegate?.handlePanEnd()
        default:
            break
        }
    }
}

struct VolumeBrightnessIndicator: View {
    let type: IndicatorType
    let value: Double
    let isVisible: Bool

    enum IndicatorType {
        case volume
        case brightness
    }

    private var iconName: String {
        switch type {
        case .volume:
            if value <= 0 { return "speaker.slash.fill" }
            if value < 0.33 { return "speaker.wave.1.fill" }
            if value < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            if value < 0.33 { return "sun.min.fill" }
            if value < 0.66 { return "sun.max.fill" }
            return "sun.max.fill"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 20))
            Text("\(Int(value * 100))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isVisible)
    }
}

struct LongPressSpeedIndicator: View {
    let speed: Float
    let isVisible: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 16))
            Text("\(String(format: "%.1f", speed))x 倍速中")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isVisible)
    }
}

struct DoubleTapSeekIndicatorView: View {
    let isForward: Bool
    let seconds: Int
    let isVisible: Bool

    var body: some View {
        HStack {
            if !isForward {
                indicatorContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if isForward {
                indicatorContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .allowsHitTesting(false)
    }

    private var indicatorContent: some View {
        VStack(spacing: 6) {
            Image(systemName: isForward ? "forward.30.fill" : "backward.30.fill")
                .font(.system(size: 24))
            Text("\(isForward ? "快进" : "快退")\(seconds)秒")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white)
        .background(
            LinearGradient(
                colors: isForward
                    ? [Color.clear, Color.black.opacity(0.25)]
                    : [Color.black.opacity(0.25), Color.clear],
                startPoint: .center,
                endPoint: isForward ? .trailing : .leading
            )
        )
    }
}

#else

struct PlayerGestureOverlay: View {
    var body: some View {
        Color.clear
    }
}

@MainActor
final class PlayerGestureDelegate: ObservableObject {
    @Published var showBrightnessIndicator: Bool = false
    @Published var brightnessValue: Double = 0.5
    @Published var showVolumeIndicator: Bool = false
    @Published var volumeValue: Double = 0.5
    @Published var showLongPressIndicator: Bool = false
    @Published var longPressSpeed: Float = 2.0
    @Published var showForwardSeek: Bool = false
    @Published var showBackwardSeek: Bool = false
    @Published var seekAccumulatedSeconds: Int = 0

    var isLive: Bool = false
    var isLocked: Bool = false
    var enableQuickDouble: Bool = true
    var fastForBackwardDuration: Int = 10
    var onToggleControls: (() -> Void)?
    var onDoubleTap: ((PlayerDoubleTapZone) -> Void)?
    var onLongPressStart: (() -> Void)?
    var onLongPressEnd: (() -> Void)?
    var onHorizontalSeek: ((CGFloat) -> Void)?
    var onBrightnessChange: ((CGFloat) -> Void)?
    var onVolumeChange: ((CGFloat) -> Void)?
    var onFullScreenGesture: ((Bool) -> Void)?
    var onGestureEnd: (() -> Void)?

    func setViewWidth(_ width: CGFloat) {}
}

struct VolumeBrightnessIndicator: View {
    let type: IndicatorType
    let value: Double
    let isVisible: Bool

    enum IndicatorType {
        case volume
        case brightness
    }

    var body: some View {
        EmptyView()
    }
}

struct LongPressSpeedIndicator: View {
    let speed: Float
    let isVisible: Bool

    var body: some View {
        EmptyView()
    }
}

struct DoubleTapSeekIndicatorView: View {
    let isForward: Bool
    let seconds: Int
    let isVisible: Bool

    var body: some View {
        EmptyView()
    }
}

#endif
