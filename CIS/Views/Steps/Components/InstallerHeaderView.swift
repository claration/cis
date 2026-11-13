//
//  InstallerHeaderView.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit

internal final class InstallerHeaderView: NSView {

    // MARK: Views

    // sexy
    private let gradientLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0.0, y: 0.5)
        layer.endPoint = CGPoint(x: 1.0, y: 0.5)
        return layer
    }()

    private let gradientBackgroundView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        return view
    }()

    private let iconImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }()

    internal let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.boldSystemFont(ofSize: 15)
        label.textColor = .labelColor
        label.alignment = .left
        return label
    }()

    internal let descriptionLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        return label
    }()

    private lazy var textStackView: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        [titleLabel, descriptionLabel].forEach {
            stack.addArrangedSubview($0)
        }
        return stack
    }()

    // MARK: Setup

    init(dmg: DMG) {
        super.init(frame: .zero)

        let customColor = dmg.color ?? .systemPink
        gradientLayer.colors = [customColor.cgColor, NSColor.white.cgColor]
        iconImageView.image = dmg.icon ?? NSApp.applicationIconImage

        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = gradientBackgroundView.bounds
    }

    private func setupView() {
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.white.cgColor

        gradientBackgroundView.layer?.addSublayer(gradientLayer)

        [gradientBackgroundView, iconImageView, textStackView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            gradientBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            gradientBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradientBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gradientBackgroundView.widthAnchor.constraint(equalToConstant: 160),

            iconImageView.centerXAnchor.constraint(equalTo: gradientBackgroundView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: gradientBackgroundView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 52),
            iconImageView.heightAnchor.constraint(equalToConstant: 52),

            textStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStackView.leadingAnchor.constraint(equalTo: gradientBackgroundView.trailingAnchor, constant: 16),
            textStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            descriptionLabel.leadingAnchor.constraint(equalTo: textStackView.leadingAnchor, constant: 8)
        ])
    }
}
