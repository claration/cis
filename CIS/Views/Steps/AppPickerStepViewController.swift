//
//  AppPickerStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit
internal import class DMG.DMGNode

internal final class AppPickerStepViewController: BannerStepViewController {
    internal var onSelectionChanged: (() -> Void)?

    // MARK: Views

    private let topMessageLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: .l(.pickerChoose(model: ProcessInfo.processInfo.marketingModel)))
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }()

    private let scrollView: NSScrollView = {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.scrollerStyle = .legacy
        return scroll
    }()

    private let tableView: NSTableView = {
        let table = NSTableView()
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = true
        table.backgroundColor = .clear
        table.rowHeight = 36
        table.selectionHighlightStyle = .none
        return table
    }()

    // MARK: Setup

    internal override init(dmg: DMG) {
        super.init(dmg: dmg)

        self.headerView.titleLabel.stringValue = .l(.pickerTitle)
        self.headerView.descriptionLabel.stringValue = .l(.pickerDescription)
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AppCellColumn"))
        column.width = 400
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView

        [topMessageLabel, scrollView].forEach {
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
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }
}

extension AppPickerStepViewController: NSTableViewDataSource, NSTableViewDelegate {

    // MARK: Delegate

    internal func numberOfRows(in tableView: NSTableView) -> Int {
        dmg.nodes.count
    }

    internal func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellView: AppPickerCellView

        if let reused = tableView.makeView(withIdentifier: AppPickerCellView.reuseIdentifier, owner: self) as? AppPickerCellView {
            cellView = reused
        } else {
            cellView = AppPickerCellView(frame: .zero)
            cellView.identifier = AppPickerCellView.reuseIdentifier
        }

        let node = dmg.nodes[row]
        let isSelected = dmg.nodesToInstall.contains(where: { $0.name == node.name })

        cellView.configure(
            with: node,
            isSelected: isSelected,
            index: row,
            target: self,
            action: #selector(checkboxToggled(_:)),
            volume: dmg.volume
        )

        return cellView
    }
}

extension AppPickerStepViewController {

    // MARK: Actions

    @objc private func checkboxToggled(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0 && index < dmg.nodes.count else {
            return
        }

        let node = dmg.nodes[index]
        if sender.state == .on {
            if !dmg.nodesToInstall.contains(where: { $0.name == node.name }) {
                dmg.nodesToInstall.append(node)
            }
        } else {
            dmg.nodesToInstall.removeAll(where: { $0.name == node.name })
        }

        onSelectionChanged?()
    }

}
