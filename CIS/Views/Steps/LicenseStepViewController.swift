//
//  LicenseStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit
internal import class DMG.DMGLicense

internal final class LicenseStepViewController: BannerStepViewController {

    // MARK: Views

    private let topMessageLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: .l(.licenseAcceptRead))
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

        self.headerView.titleLabel.stringValue = .l(.licenseTitle)
        self.headerView.descriptionLabel.stringValue = .l(.licenseDescription(appName: dmg.name))
        self.bottomMessageLabel.stringValue = .l(.licenseAcceptRequired(appName: dmg.name))

        self.licenseTextView.isEditable = false
        self.licenseTextView.isSelectable = true

        if let licenseText = extractTextFromLicense(for: dmg.licenses) {
            self.licenseTextView.string = licenseText
        }
    }

    private func extractTextFromLicense(for licenses: [DMGLicense]) -> String? {
        guard let license = dmg.licenses.first else {
            return nil
        }

        let attributed = license.rtfData.flatMap {
            NSAttributedString(rtf: $0, documentAttributes: nil)
        }

        guard
            let text = attributed?.string ?? license.text,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return text
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
