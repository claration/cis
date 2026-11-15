//
//  DMG.swift
//  CIS
//
//  Created by samsam on 11/15/26.
//

internal import AppKit
internal import class DMG.DMGNode
internal import protocol DMG.DMGVolume

internal final class AppPickerCellView: NSTableCellView {
    internal static let reuseIdentifier = NSUserInterfaceItemIdentifier("AppPickerCell")

    // MARK: Views

    private let stackView: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7.5
        return stack
    }()

    internal let checkbox: NSButton = {
        let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        return button
    }()

    internal let iconImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }()

    internal let nameLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }()

    // MARK: Setup

    internal override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        [checkbox, iconImageView, nameLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview($0)
        }

        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 18),
            iconImageView.heightAnchor.constraint(equalToConstant: 18),

            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    internal func configure(
        with node: DMGNode,
        isSelected: Bool,
        index: Int,
        target: AnyObject,
        action: Selector,
        volume: any DMGVolume
    ) {
        checkbox.tag = index
        checkbox.state = isSelected ? .on : .off
        checkbox.target = target
        checkbox.action = action

        nameLabel.stringValue = node.name.lowercased().hasSuffix(".app")
            ? String(node.name.dropLast(4))
            : node.name

        if let icon = node.nodeIcon(in: volume) {
            iconImageView.image = icon
        } else {
            iconImageView.image = NSApp.applicationIconImage
        }
    }
}
