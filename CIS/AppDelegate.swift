//
//  AppDelegate.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit
internal import struct UniformTypeIdentifiers.UTType

internal final class AppDelegate: NSObject, NSApplicationDelegate {
    internal var window: NSWindow?
    internal var launchedWithDMG = false

    internal func applicationDidFinishLaunching(_ aNotification: Notification) {
        #if DEBUG
        let debugDMGPath = URL(fileURLWithPath: "/Users/petals/Documents/stupiddiskimageinstaller/Examples/Discord.dmg")
        if FileManager.default.fileExists(atPath: debugDMGPath.relativePath) {
            launchedWithDMG = true
            openInstallerWindow(with: debugDMGPath)
            return
        }
        #else
        // Ideally, the app should only be opened when a user double pressed
        // on a DMG file, otherwise we should force our app to be default.
        if !launchedWithDMG {
            NSWorkspace.setDefaultFileForApplication(
                url: Bundle.main.bundleURL,
                toOpen: UTType(filenameExtension: "dmg")!
            )
        }
        #endif
    }

    internal func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let filename = URL(fileURLWithPath: filename)

        if filename.pathExtension.lowercased() == "dmg" {
            launchedWithDMG = true
            openInstallerWindow(with: filename)
            return true
        }
        return false
    }

    internal func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let filename = URL(fileURLWithPath: filename)

            if filename.pathExtension.lowercased() == "dmg" {
                launchedWithDMG = true
                openInstallerWindow(with: filename)
                break
            }
        }
    }

    internal func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func openInstallerWindow(with dmgPath: URL) {
        if let window {
            NSAlert.showAlert(
                title: "Failed to Open DMG File",
                message: .l(.duplicateWindow),
                style: .warning
            )
            window.makeKeyAndOrderFront(nil)
            return
        }

        do {
            let dmg = try DMG(for: dmgPath)

            let window = NSWindow(
                contentRect: dmg.isPkg ? Self.miniFrame : Self.frame,
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )

            window.representedURL = dmgPath

            if dmg.isPkg {
                window.contentViewController = PKGInstallerViewController(dmg: dmg)
                window.titlebarAppearsTransparent = true
            } else {
                window.contentViewController = InstallerViewController(dmg: dmg)
                window.title = .l(.setup(appName: dmg.name))
                window.appearance = NSAppearance(named: .aqua)
            }

            window.center()
            window.makeKeyAndOrderFront(nil)

            NSApp.activate(ignoringOtherApps: true)

            if let icon = dmg.icon {
                NSApplication.shared.setApplicationIconBadgeImage(with: icon)
            }

            self.window = window
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

    @objc private func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel()
    }
}

extension AppDelegate {
    /// Convenience constant for getting the intended window size/frame.
    static internal let frame = NSRect(x: 0, y: 0, width: 500, height: 360)
    static internal let miniFrame = NSRect(x: 0, y: 0, width: 400, height: 45)
}
