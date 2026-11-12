//
//  LicenseStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

import AppKit

internal final class LicenseStepViewController: BannerStepViewController {

    // MARK: Views

    private let topMessageLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "Press Page Down to see the rest of the agreement.")
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }()

    private let scrollView: NSScrollView = {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.scrollerStyle = .legacy
        return scroll
    }()

    private var licenseTextView: NSTextView {
        return scrollView.documentView as! NSTextView
    }

    private let bottomMessageLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }()

    // MARK: Setup

    internal override init(dmg: DMG) {
        super.init(dmg: dmg)

        let appName = self.dmg.name

        self.headerView.titleLabel.stringValue = "License Agreement"
        self.headerView.descriptionLabel.stringValue = "Please review the license terms before installing \(appName)."
        self.bottomMessageLabel.stringValue = "If you accept the terms of the agreement, click I Agree to continue. You must accept the agreement to install \(appName)."

        self.licenseTextView.isEditable = false
        self.licenseTextView.isSelectable = true
        if let licenseText = dmg.licenseText {
            self.licenseTextView.string = licenseText
        }
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal override func viewDidAppear() {
        super.viewDidAppear()
        // this is so macos isnt annoying and needing you to click
        // before being able to press Page Up/Down
        view.window?.makeFirstResponder(self.licenseTextView)
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()

        [topMessageLabel, scrollView, bottomMessageLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            topMessageLabel.topAnchor.constraint(equalTo: headerViewSeperatorBox.bottomAnchor, constant: 16),
            topMessageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            topMessageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: topMessageLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            bottomMessageLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            bottomMessageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bottomMessageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bottomMessageLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }
}
