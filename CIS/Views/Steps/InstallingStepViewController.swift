//
//  InstallingStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

import AppKit

internal final class InstallingStepViewController: BannerStepViewController {
    internal var onCompletion: (() -> Void)?

    // MARK: Views

    private let topMessageLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "Idle")
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }()

    private let progressIndicator: NSProgressIndicator = {
        let spinner = NSProgressIndicator()
        spinner.style = .bar
        spinner.isIndeterminate = true
        return spinner
    }()

    private let showDetailsButton: NSButton = {
        let button = NSButton(title: "Show Details", target: nil, action: nil)
        button.bezelStyle = .rounded
        return button
    }()

    private let scrollView: NSScrollView = {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.scrollerStyle = .legacy
        scroll.isHidden = true
        return scroll
    }()

    private var logTextView: NSTextView {
        return scrollView.documentView as! NSTextView
    }

    // MARK: Setup

    internal override init(dmg: DMG) {
        super.init(dmg: dmg)

        let appName = self.dmg.name
        self.headerView.titleLabel.stringValue = "Installing"
        self.headerView.descriptionLabel.stringValue = "Please wait while \(appName) is being installed."

        setupLogTextView()
        setupActions()
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLogTextView() {
        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }

    private func setupActions() {
        showDetailsButton.target = self
        showDetailsButton.action = #selector(toggleDetails)
    }

    @objc private func toggleDetails() {
        showDetailsButton.isHidden = false
        showDetailsButton.isHidden = true
        scrollView.isHidden = false
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()

        [topMessageLabel, progressIndicator, showDetailsButton, scrollView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            topMessageLabel.topAnchor.constraint(equalTo: headerViewSeperatorBox.bottomAnchor, constant: 16),
            topMessageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            topMessageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            progressIndicator.topAnchor.constraint(equalTo: topMessageLabel.bottomAnchor, constant: 12),
            progressIndicator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            progressIndicator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            showDetailsButton.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 12),
            showDetailsButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            scrollView.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.heightAnchor.constraint(equalToConstant: 150)
        ])
    }

    internal func startInstallation() {
        progressIndicator.startAnimation(nil)

        Task { [weak self] in
            guard let self = self else { return }

            do {
                let apps = try self.dmg.lookup()

                try await self.dmg.install(apps) { statusMessage in
                    await MainActor.run {
                        let isDone = statusMessage.contains("... 100%")

                        if !isDone {
                            self.topMessageLabel.stringValue = statusMessage
                        }

                        var text = self.logTextView.string
                        if isDone, let range = text.range(of: "\n", options: .backwards) {
                            text = String(text[..<range.lowerBound]) + "\n" + statusMessage
                        } else {
                            text = text.isEmpty ? statusMessage : text + "\n" + statusMessage
                        }

                        self.logTextView.string = text
                        self.logTextView.scrollRangeToVisible(NSRange(location: text.count, length: 0))
                    }
                }

                await MainActor.run {
                    self.progressIndicator.stopAnimation(nil)
                    self.progressIndicator.isIndeterminate = false
                    self.progressIndicator.doubleValue = 100.0
                    self.topMessageLabel.stringValue = "Installation completed successfully!"

                    let completionMsg = "Installation completed successfully."
                    self.logTextView.string += "\n\(completionMsg)"
                    let range = NSRange(location: self.logTextView.string.count, length: 0)
                    self.logTextView.scrollRangeToVisible(range)

                    self.onCompletion?()
                }
            } catch {
                await MainActor.run {
                    self.progressIndicator.stopAnimation(nil)
                    let errorMsg = "Installation failed: \(error.localizedDescription)"
                    self.topMessageLabel.stringValue = errorMsg

                    self.logTextView.string += "\n\(errorMsg)"
                    let range = NSRange(location: self.logTextView.string.count, length: 0)
                    self.logTextView.scrollRangeToVisible(range)
                }
            }
        }
    }
}
