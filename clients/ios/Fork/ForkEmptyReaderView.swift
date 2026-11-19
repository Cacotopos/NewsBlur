//
//  ForkEmptyReaderView.swift
//  NewsBlur iPad fork — fork-only file, never upstreamed. See fork-docs/.
//

import UIKit

/// "Clear horizon" filler for the reader while no story is open (user's pick, 2026-11-20):
/// the Cacotopic eclipse over its horizon, a title, and a hint that follows the layout.
///
/// `ForkRootViewController` lays it over the reader and shows it only while upstream's reader has no
/// story. It ignores touches, so the reader's own header buttons still work through it.
final class ForkEmptyReaderView: UIView {
    private let mark = MarkView()
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private var lastTheme = ""

    /// True while the rail and feed column sit beside the reader; false while they're behind the menu.
    var columnsDocked = true {
        didSet { if columnsDocked != oldValue { updateHint() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        titleLabel.text = NSLocalizedString("The horizon is clear", comment: "Fork empty reader title")
        titleLabel.textAlignment = .center
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [mark, titleLabel, hintLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(28, after: mark)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 200),
            mark.heightAnchor.constraint(equalToConstant: 170),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        updateHint()
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Re-reads colours when upstream's theme changes. Cheap to call every refresh tick.
    func applyThemeIfChanged() {
        guard ForkTheme.current != lastTheme else { return }
        applyTheme()
    }

    private func applyTheme() {
        lastTheme = ForkTheme.current
        // Avenir Next stands in for the start-up screen's Century Gothic, which iPadOS doesn't ship.
        titleLabel.font = UIFont(name: "AvenirNext-Medium", size: 22) ?? .systemFont(ofSize: 22, weight: .medium)
        hintLabel.font = UIFont(name: "AvenirNext-Regular", size: 15) ?? .systemFont(ofSize: 15)
        titleLabel.textColor = ForkTheme.text
        hintLabel.textColor = ForkTheme.secondaryText
        mark.moonColor = ForkTheme.columnBackground
    }

    private func updateHint() {
        hintLabel.text = columnsDocked
            ? NSLocalizedString("Pick a story from the list to start reading.", comment: "Fork empty reader hint, columns showing")
            : NSLocalizedString("Tap the menu button to choose a feed.", comment: "Fork empty reader hint, menu hidden")
        accessibilityLabel = [titleLabel.text, hintLabel.text].compactMap { $0 }.joined(separator: ". ")
    }

    /// The eclipse mark, drawn like `fork-docs/artwork/render_cacotopic.swift` ("Finer lines", main line
    /// at 80%), with the moon filled in the reader's background colour so it suits every theme.
    private final class MarkView: UIView {
        var moonColor: UIColor = .black { didSet { setNeedsDisplay() } }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            contentMode = .redraw
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func draw(_ rect: CGRect) {
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            let amber = UIColor(red: 1, green: 0xB2 / 255.0, blue: 0x3F / 255.0, alpha: 1)
            let ember = UIColor(red: 1, green: 0x7A / 255.0, blue: 0x3D / 255.0, alpha: 1)
            // Design space: sun radius 240, glow reaching 372 above its centre, horizon 330 below it and the
            // second line 44 further down, so the whole mark is about 760 tall.
            let s = bounds.height / 760
            let r = 240 * s
            let c = CGPoint(x: bounds.midX, y: 375 * s)
            let horizonY = c.y + 330 * s

            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: bounds.width, height: horizonY))
            let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [amber.withAlphaComponent(0.45).cgColor, ember.withAlphaComponent(0.15).cgColor,
                                           ember.withAlphaComponent(0).cgColor] as CFArray,
                                  locations: [0, 0.6, 1])!
            ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * 1.55, options: [])
            ctx.restoreGState()

            ctx.setLineCap(.round)
            ctx.setLineWidth(16 * s)
            ctx.setStrokeColor(amber.withAlphaComponent(0.8).cgColor)
            ctx.move(to: CGPoint(x: c.x - 320 * s, y: horizonY)); ctx.addLine(to: CGPoint(x: c.x + 320 * s, y: horizonY))
            ctx.strokePath()
            ctx.setLineWidth(12 * s)
            ctx.setStrokeColor(amber.withAlphaComponent(0.45).cgColor)
            ctx.move(to: CGPoint(x: c.x - 190 * s, y: horizonY + 44 * s)); ctx.addLine(to: CGPoint(x: c.x + 190 * s, y: horizonY + 44 * s))
            ctx.strokePath()

            ctx.setFillColor(amber.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            let k = r / 255
            ctx.setFillColor(moonColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - 240 * k, y: c.y - 252 * k, width: 490 * k, height: 490 * k))
            let bead = CGPoint(x: c.x + cos(-.pi / 4) * 252 * k, y: c.y + sin(-.pi / 4) * 252 * k)
            let shine = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [UIColor.white.withAlphaComponent(0.95).cgColor, amber.withAlphaComponent(0.6).cgColor,
                                            amber.withAlphaComponent(0).cgColor] as CFArray,
                                   locations: [0, 0.25, 1])!
            ctx.drawRadialGradient(shine, startCenter: bead, startRadius: 0, endCenter: bead, endRadius: 70 * k, options: [])
        }
    }
}
