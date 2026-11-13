//
//  StepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit

internal class BannerStepViewController: NSViewController {
    internal var dmg: DMG

    // MARK: Views

    internal lazy var headerView = InstallerHeaderView(dmg: dmg)

    internal let headerViewSeperatorBox: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        return box
    }()

    // MARK: Setup

    internal init(dmg: DMG) {
        self.dmg = dmg
        super.init(nibName: nil, bundle: nil)
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal override func loadView() {
        self.view = NSView()

        [headerView, headerViewSeperatorBox].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 60),

            headerViewSeperatorBox.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            headerViewSeperatorBox.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerViewSeperatorBox.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerViewSeperatorBox.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
}
