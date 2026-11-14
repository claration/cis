//
//  LocationStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit

internal final class LocationStepViewController: BannerStepViewController {

    // MARK: Views

    private let topMessageLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "Setup will install the application in the following folder. To install in a different folder, click Browse and select another folder.")
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }()

    private let pathTextField: NSTextField = {
        let tf = NSTextField()
        tf.isEditable = true
        tf.isBordered = true
        tf.drawsBackground = true
        tf.backgroundColor = .textBackgroundColor
        tf.font = NSFont.systemFont(ofSize: 13)
        return tf
    }()

    private let browseButton: NSButton = {
        let button = NSButton()
        button.title = .l(.locationBrowseButton)
        button.bezelStyle = .rounded
        return button
    }()

    private let destinationBox: NSBox = {
        let box = NSBox()
        box.boxType = .primary
        box.title = .l(.locationBrowseTitle)
        box.titleFont = NSFont.boldSystemFont(ofSize: 11)
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }()

    private let spaceRequiredLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        return label
    }()

    private let spaceAvailableLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        return label
    }()

    // MARK: Setup

    internal override init(dmg: DMG) {
        super.init(dmg: dmg)

        self.headerView.titleLabel.stringValue = .l(.locationTitle)
        self.headerView.descriptionLabel.stringValue = .l(.locationDescription(appName: dmg.name))
        self.pathTextField.stringValue = self.dmg.destinationFolderPath.relativePath
        self.spaceRequiredLabel.stringValue = .l(.locationSpaceRequired(
            formattedBytes: dmg.virtualSize.formattedBytes()
        ))
        if let remainingSpace = ProcessInfo.processInfo.remainingSpace() {
            self.spaceAvailableLabel.stringValue = .l(.locationSpaceAvailable(
                formattedBytes: remainingSpace
            ))
        }
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()

        browseButton.target = self
        browseButton.action = #selector(browseClicked)

        [topMessageLabel, destinationBox, spaceRequiredLabel, spaceAvailableLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        [pathTextField, browseButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            destinationBox.contentView?.addSubview($0)
        }

        NSLayoutConstraint.activate([
            topMessageLabel.topAnchor.constraint(equalTo: headerViewSeperatorBox.bottomAnchor, constant: 16),
            topMessageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            topMessageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            destinationBox.topAnchor.constraint(equalTo: topMessageLabel.bottomAnchor, constant: 50),
            destinationBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            destinationBox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            destinationBox.heightAnchor.constraint(equalToConstant: 75),

            pathTextField.leadingAnchor.constraint(equalTo: destinationBox.contentView!.leadingAnchor, constant: 16),
            pathTextField.centerYAnchor.constraint(equalTo: destinationBox.contentView!.centerYAnchor),
            pathTextField.trailingAnchor.constraint(equalTo: browseButton.leadingAnchor, constant: -12),
            pathTextField.heightAnchor.constraint(equalToConstant: 24),

            browseButton.trailingAnchor.constraint(equalTo: destinationBox.contentView!.trailingAnchor, constant: -16),
            browseButton.centerYAnchor.constraint(equalTo: destinationBox.contentView!.centerYAnchor),
            browseButton.widthAnchor.constraint(equalToConstant: 90),

            spaceRequiredLabel.topAnchor.constraint(equalTo: destinationBox.bottomAnchor, constant: 16),
            spaceRequiredLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            spaceAvailableLabel.topAnchor.constraint(equalTo: spaceRequiredLabel.bottomAnchor, constant: 4),
            spaceAvailableLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            spaceAvailableLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])
    }

}

extension LocationStepViewController {

    // MARK: Actions

    @objc private func browseClicked() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = .l(.locationPromptTitle)
        openPanel.message = .l(.locationPromptDescription)

        if let window = view.window {
            openPanel.beginSheetModal(for: window) { [weak self] response in
                if
                    response == .OK,
                    let url = openPanel.url
                {
                    self?.dmg.destinationFolderPath = url
                    self?.pathTextField.stringValue = url.relativePath
                }
            }
        } else {
            if
                openPanel.runModal() == .OK,
                let url = openPanel.url
            {
                self.dmg.destinationFolderPath = url
                self.pathTextField.stringValue = url.relativePath
            }
        }
    }
}
