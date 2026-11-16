//
//  PkgInstallerViewController.swift
//  CIS
//
//  Created by samsam on 11/15/26.
//

internal import AppKit

internal final class PKGInstallerViewController: NSViewController {
    internal var dmg: DMG

    // MARK: Views

    private let iconImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }()

    private let topMessageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        return label
    }()

    private let progressIndicator: NSProgressIndicator = {
        let spinner = NSProgressIndicator()
        spinner.style = .bar
        spinner.controlSize = .mini
        spinner.isIndeterminate = true
        return spinner
    }()

    private let textProgressStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }()

    private let contentStackView: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }()

    // MARK: Setup

    internal init(dmg: DMG) {
        self.dmg = dmg
        super.init(nibName: nil, bundle: nil)

        if let icon = dmg.icon {
            self.iconImageView.image = NSApplication.shared.genApplicationIconBadgeImage(with: icon)
        } else {
            self.iconImageView.image = NSApp.applicationIconImage
        }

        self.topMessageLabel.stringValue = .l(.pkgInstallingTitle(fileName: dmg.filePath.lastPathComponent))
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal override func loadView() {
        self.view = NSView(frame: AppDelegate.miniFrame)
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()

        [topMessageLabel, progressIndicator].forEach {
            textProgressStack.addArrangedSubview($0)
        }

        [iconImageView, textProgressStack].forEach {
            contentStackView.addArrangedSubview($0)
        }

        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 36),
            iconImageView.heightAnchor.constraint(equalToConstant: 36),

            progressIndicator.widthAnchor.constraint(equalTo: textProgressStack.widthAnchor),

            contentStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            contentStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            contentStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            contentStackView.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 2),
            contentStackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -2)
        ])

        progressIndicator.startAnimation(nil)

        extractAndOpen()
    }

    private func extractAndOpen() {
        Task {
            do {
                try await dmg.openNodes()
                NSApp.terminate(nil)
            } catch {
                NSAlert.showAlert(
                    title: "Failed to Extract Package",
                    message: "Error: \(error.localizedDescription)",
                    style: .warning
                )
            }
        }
    }
}
