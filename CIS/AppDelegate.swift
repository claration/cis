//
//  AppDelegate.swift
//  CIS
//
//  Created by samsam on 11/11/26.
//

internal import AppKit

internal final class AppDelegate: NSObject, NSApplicationDelegate {
    private var activeWindows: Set<NSWindow> = []
    private var hasOpenedDmg: Bool = false

    internal func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupMainMenu()
        if !hasOpenedDmg {
            let window = CISWindow(toolbarStyle: .unifiedCompact)
            window.title = .l(.settingsTitle)
            window.contentViewController = SettingsViewController()
            window.center()
            window.makeKeyAndOrderFront(nil)
            track(window)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    internal func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)

        if url.pathExtension.lowercased() == "dmg" {
            openInstallerWindow(with: url)
            hasOpenedDmg = true
            return true
        } else {
            return false
        }
    }

    internal func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            if url.pathExtension.lowercased() == "dmg" {
                openInstallerWindow(with: url)
                hasOpenedDmg = true
            }
        }
    }

    internal func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func openInstallerWindow(with dmgPath: URL) {
        do {
            let dmg = try DMG(for: dmgPath)
            let window = CISWindow()

            if dmg.isPkg {
                window.contentViewController = ExtractorViewController(dmg: dmg)
                window.titlebarAppearsTransparent = true
            } else {
                window.contentViewController = InstallerViewController(dmg: dmg)
                window.title = .l(.setup(appName: dmg.name))
                window.representedURL = dmgPath
                if !Preferences.useSystemAppearence {
                    window.appearance = NSAppearance(named: .aqua)
                }
            }

            window.center()
            window.makeKeyAndOrderFront(nil)
            track(window)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            NSAlert.showAlert(
                title: "Failed to Open DMG File",
                message: """
                Error: \(error.localizedDescription)
                
                \(String.l(.openInstead(appName: "Disk Image Mounter")))
                """,
                style: .critical,
                buttonTitles: [.l(.open(appName: "Disk Image Mounter")), .l(.noThanks)]
            ) { response in
                if response == .alertFirstButtonReturn {
                    Process.runProcess(
                        executable: "/usr/bin/open",
                        arguments: ["-a", "DiskImageMounter", dmgPath.relativePath]
                    )
                }
            }
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let aboutItem = NSMenuItem(title: .l(.about(appName: Bundle.main.name)), action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: .l(.quit(appName: Bundle.main.name)), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApp.windowsMenu = NSMenu()
        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel()
    }

    private func track(_ window: NSWindow) {
        activeWindows.insert(window)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let closingWindow = notification.object as? NSWindow else { return }
            self?.activeWindows.remove(closingWindow)
        }
    }
}
