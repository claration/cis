//
//  WizardStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

import AppKit

internal class WizardStepViewController: NSViewController {
    internal let dmg: DMG

    // MARK: Views

    private let sidebarBackgroundView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        return view
    }()

    private let splashImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.image = NSImage(named: "InstallerGlyph")
        imageView.imageScaling = .scaleAxesIndependently

        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }()

    private let iconImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }()

    internal let titleLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = NSFont.boldSystemFont(ofSize: 16)
        return label
    }()

    internal let descriptionLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        return label
    }()

    // MARK: Setup

    internal init(dmg: DMG) {
        self.dmg = dmg
        super.init(nibName: nil, bundle: nil)

        sidebarBackgroundView.layer?.backgroundColor = (dmg.color ?? .systemPink).cgColor
        iconImageView.image = dmg.icon ?? NSApp.applicationIconImage
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal override func loadView() {
        self.view = NSView()
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.white.cgColor

        [sidebarBackgroundView, splashImageView, iconImageView, titleLabel, descriptionLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            sidebarBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarBackgroundView.widthAnchor.constraint(equalToConstant: 164),

            splashImageView.leadingAnchor.constraint(equalTo: sidebarBackgroundView.leadingAnchor),
            splashImageView.topAnchor.constraint(equalTo: sidebarBackgroundView.topAnchor),
            splashImageView.bottomAnchor.constraint(equalTo: sidebarBackgroundView.bottomAnchor),
            splashImageView.widthAnchor.constraint(equalTo: sidebarBackgroundView.widthAnchor),

            iconImageView.topAnchor.constraint(equalTo: sidebarBackgroundView.topAnchor, constant: 16),
            iconImageView.trailingAnchor.constraint(equalTo: sidebarBackgroundView.trailingAnchor, constant: -16),
            iconImageView.widthAnchor.constraint(equalToConstant: 75),
            iconImageView.heightAnchor.constraint(equalToConstant: 75),

            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: sidebarBackgroundView.trailingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: sidebarBackgroundView.trailingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
}
