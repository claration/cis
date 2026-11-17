//
//  LocationOptionButton.swift
//  CIS
//
//  Created by samsam on 11/16/26.
//

internal import AppKit

internal final class LocationOptionButton: NSBox {

    // MARK: Properties

    internal var onSelect: (() -> Void)?

    internal var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    private let iconView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }()

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        return label
    }()

    // MARK: Setup

    internal init(icon: NSImage?, title: String) {
        super.init(frame: .zero)
        iconView.image = icon
        titleLabel.stringValue = title
        setupBox()
        setupLayout()
        updateAppearance()
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBox() {
        boxType = .custom
        cornerRadius = 5
        borderWidth = 1
        fillColor = .controlBackgroundColor
    }

    private func setupLayout() {
        let stack = NSStackView(views: [iconView, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView = NSView()
        contentView?.addSubview(stack)

        if let contentView {
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 40),
                iconView.heightAnchor.constraint(equalToConstant: 40),

                stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
                stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
                stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
            ])
        }
    }

    private func updateAppearance() {
        borderColor = isSelected ? .controlAccentColor : .separatorColor
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
    }

    // MARK: Events

    internal override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onSelect?()
        }
    }
}
