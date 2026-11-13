import Foundation
import UIKit
import TelegramUIPreferences

// URGRAM (ambience — snow): a gentle falling-snow layer over the whole app
// window, with snow caps that slowly accumulate on the top and bottom
// edges of the screen. The view is attached to the main window's
// container view (above the root controller and its navigation bars, so
// snow falls over the chat list, inside chats and over the bars), it never
// intercepts touches (isUserInteractionEnabled = false), and it lives
// inside the app's own window — the keyboard and system alerts are
// separate windows and are never covered.
//
// Falling snow is a CAEmitterLayer with a programmatically drawn soft
// flake (radial-gradient disc — no image asset). Accumulation is the
// classic cheap illusion: two wavy-edged white caps whose height grows
// linearly over minutes to a small cap (top 5pt, bottom 7pt). Caps are
// in-memory only: toggling snow off (which destroys this view), changing
// intensity, or relaunching the app resets ("melts") them. Emission
// pauses while the app is backgrounded.
//
// Intensity presets (birth rates are flakes/second across both cells):
// - light (0):  ~6/s,  fall speed 28–45 pt/s, full caps in ~12 minutes
// - medium (1): ~14/s, fall speed 35–60 pt/s, full caps in ~8 minutes
// - heavy (2):  ~30/s, fall speed 45–80 pt/s, full caps in ~5 minutes

private func urgramSnowflakeImage(diameter: CGFloat) -> UIImage? {
    let size = CGSize(width: diameter, height: diameter)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        let colors = [UIColor.white.withAlphaComponent(0.95).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
        let locations: [CGFloat] = [0.0, 1.0]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else {
            return
        }
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: size.width / 2.0, options: [])
    }
}

private func urgramSnowCapPath(width: CGFloat, height: CGFloat, atBottom: Bool, viewHeight: CGFloat) -> CGPath {
    let path = UIBezierPath()
    // Sum of two sine waves with fixed phases: an irregular but stable
    // edge (recomputed identically for a given width, so it never
    // shimmers between growth ticks).
    let wave: (CGFloat) -> CGFloat = { x in
        let normalized = 0.62 + 0.21 * sin(x * 0.021 + 1.7) + 0.17 * sin(x * 0.047 + 0.4)
        return height * normalized
    }
    if atBottom {
        let baseY = viewHeight
        path.move(to: CGPoint(x: 0.0, y: baseY))
        var x: CGFloat = 0.0
        while x <= width {
            path.addLine(to: CGPoint(x: x, y: baseY - wave(x)))
            x += 4.0
        }
        path.addLine(to: CGPoint(x: width, y: baseY - wave(width)))
        path.addLine(to: CGPoint(x: width, y: baseY))
    } else {
        path.move(to: CGPoint(x: 0.0, y: 0.0))
        var x: CGFloat = 0.0
        while x <= width {
            path.addLine(to: CGPoint(x: x, y: wave(x)))
            x += 4.0
        }
        path.addLine(to: CGPoint(x: width, y: wave(width)))
        path.addLine(to: CGPoint(x: width, y: 0.0))
    }
    path.close()
    return path.cgPath
}

final class UrgramSnowView: UIView {
    private let emitterLayer = CAEmitterLayer()
    private let topCapLayer = CAShapeLayer()
    private let bottomCapLayer = CAShapeLayer()

    private var intensity: Int = 0
    private var growthProgress: CGFloat = 0.0
    private var growthTimer: Timer?
    private var isEmissionPaused = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear

        self.emitterLayer.emitterShape = .line
        self.emitterLayer.emitterMode = .surface
        self.emitterLayer.renderMode = .oldestLast
        self.layer.addSublayer(self.emitterLayer)

        for capLayer in [self.topCapLayer, self.bottomCapLayer] {
            capLayer.fillColor = UIColor.white.withAlphaComponent(0.92).cgColor
            capLayer.opacity = 0.0
            self.layer.addSublayer(capLayer)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(self.applicationDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.applicationWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        self.growthTimer?.invalidate()
    }

    @objc private func applicationDidEnterBackground() {
        self.isEmissionPaused = true
        self.emitterLayer.speed = 0.0
        self.growthTimer?.invalidate()
        self.growthTimer = nil
    }

    @objc private func applicationWillEnterForeground() {
        self.isEmissionPaused = false
        self.emitterLayer.speed = 1.0
        self.startGrowthTimerIfNeeded()
    }

    func configure(intensity: Int) {
        self.intensity = min(2, max(0, intensity))
        self.growthProgress = 0.0
        self.updateCaps()

        let smallFlake = urgramSnowflakeImage(diameter: 11.0)
        let largeFlake = urgramSnowflakeImage(diameter: 18.0)

        let smallCell = CAEmitterCell()
        smallCell.contents = smallFlake?.cgImage
        smallCell.lifetime = 16.0
        smallCell.lifetimeRange = 4.0
        smallCell.scale = 0.55
        smallCell.scaleRange = 0.3
        smallCell.spin = 0.6
        smallCell.spinRange = 1.2
        smallCell.alphaRange = 0.35
        smallCell.emissionLongitude = .pi
        smallCell.emissionRange = 0.4

        let largeCell = CAEmitterCell()
        largeCell.contents = largeFlake?.cgImage
        largeCell.lifetime = 16.0
        largeCell.lifetimeRange = 4.0
        largeCell.scale = 0.8
        largeCell.scaleRange = 0.4
        largeCell.spin = 0.4
        largeCell.spinRange = 0.8
        largeCell.alphaRange = 0.3
        largeCell.emissionLongitude = .pi
        largeCell.emissionRange = 0.4

        switch self.intensity {
        case 2:
            smallCell.birthRate = 20.0
            smallCell.velocity = 62.0
            smallCell.velocityRange = 18.0
            largeCell.birthRate = 10.0
            largeCell.velocity = 48.0
            largeCell.velocityRange = 14.0
        case 1:
            smallCell.birthRate = 9.0
            smallCell.velocity = 48.0
            smallCell.velocityRange = 14.0
            largeCell.birthRate = 5.0
            largeCell.velocity = 38.0
            largeCell.velocityRange = 10.0
        default:
            smallCell.birthRate = 4.0
            smallCell.velocity = 36.0
            smallCell.velocityRange = 10.0
            largeCell.birthRate = 2.0
            largeCell.velocity = 30.0
            largeCell.velocityRange = 8.0
        }
        smallCell.yAcceleration = 6.0
        largeCell.yAcceleration = 6.0

        self.emitterLayer.emitterCells = [smallCell, largeCell]
        self.startGrowthTimerIfNeeded()
    }

    private var growthFullDuration: CGFloat {
        switch self.intensity {
        case 2: return 5.0 * 60.0
        case 1: return 8.0 * 60.0
        default: return 12.0 * 60.0
        }
    }

    private func startGrowthTimerIfNeeded() {
        guard !self.isEmissionPaused, self.growthProgress < 1.0, self.growthTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else {
                return
            }
            self.growthProgress = min(1.0, self.growthProgress + 1.0 / self.growthFullDuration)
            self.updateCaps()
            if self.growthProgress >= 1.0 {
                self.growthTimer?.invalidate()
                self.growthTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.growthTimer = timer
    }

    private func updateCaps() {
        let size = self.bounds.size
        guard size.width > 1.0, size.height > 1.0 else {
            return
        }
        let topHeight = 5.0 * self.growthProgress
        let bottomHeight = 7.0 * self.growthProgress
        let opacity: Float = self.growthProgress > 0.0 ? 1.0 : 0.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.topCapLayer.path = urgramSnowCapPath(width: size.width, height: topHeight, atBottom: false, viewHeight: size.height)
        self.topCapLayer.opacity = opacity
        self.bottomCapLayer.path = urgramSnowCapPath(width: size.width, height: bottomHeight, atBottom: true, viewHeight: size.height)
        self.bottomCapLayer.opacity = opacity
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = self.bounds.size
        self.emitterLayer.frame = self.bounds
        self.emitterLayer.emitterPosition = CGPoint(x: size.width / 2.0, y: -12.0)
        self.emitterLayer.emitterSize = CGSize(width: size.width, height: 1.0)
        self.topCapLayer.frame = self.bounds
        self.bottomCapLayer.frame = self.bounds
        self.updateCaps()
    }
}

// URGRAM (ambience — snow): owns the single snow view and applies
// UrgramSettings changes idempotently (the settings signal fires for every
// Urgram setting, not just the snow ones).
final class UrgramSnowOverlayManager {
    private var snowView: UrgramSnowView?
    private var appliedIntensity: Int = -1

    func apply(settings: UrgramSettings, containerView: UIView?) {
        if !settings.snowEnabled {
            if let snowView = self.snowView {
                snowView.removeFromSuperview()
                self.snowView = nil
                self.appliedIntensity = -1
            }
            return
        }
        guard let containerView = containerView else {
            return
        }
        if let snowView = self.snowView, snowView.superview !== containerView {
            snowView.removeFromSuperview()
            self.snowView = nil
            self.appliedIntensity = -1
        }
        if self.snowView == nil {
            let view = UrgramSnowView()
            view.frame = containerView.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            containerView.addSubview(view)
            self.snowView = view
        }
        if let snowView = self.snowView {
            containerView.bringSubviewToFront(snowView)
            if self.appliedIntensity != settings.snowIntensity {
                snowView.configure(intensity: settings.snowIntensity)
                self.appliedIntensity = settings.snowIntensity
            }
        }
    }
}
