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
        let debugDMGPath = URL(fileURLWithPath: "/Users/petals/Downloads/reaper767_universal.dmg")
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
                message: "Make sure an existing installer window is closed!",
                style: .warning
            )
            window.makeKeyAndOrderFront(nil)
            return
        }

        do {
            let dmg = try DMG(path: dmgPath)

            let installerVC = InstallerViewController(dmg: dmg)

            let window = NSWindow(
                contentRect: Self.frame,
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "\(dmg.name) Setup"
            window.contentViewController = installerVC

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            if let icon = dmg.icon {
                Self.setBadgedAppIcon(with: icon)
            }

            self.window = window
        } catch {
            NSAlert.showAlert(
                title: "Failed to Open DMG File",
                message: "\(error.localizedDescription)\n\nWould you like to open this file in Disk Image Mounter instead?",
                style: .critical,
                buttonTitles: ["Open Disk Image Mounter", "No Thanks"]
            ) { response in
                if response == .alertFirstButtonReturn {
                    let result = Process.runProcess(
                        executable: "/usr/bin/open",
                        arguments: ["-a", "DiskImageMounter", dmgPath.relativePath]
                    )

                    if !result.success {
                        NSAlert.showAlert(
                            title: "Failed to mount DMG",
                            message: result.output,
                            style: .warning
                        )
                    }
                }
            }
        }
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel()
    }
}

extension AppDelegate {

    /// Helper function for setting our apps icon at runtime.
    static internal func setBadgedAppIcon(with subIcon: NSImage) {
        guard let baseImage = NSApp.applicationIconImage else { return }

        let size = baseImage.size
        let combinedImage = NSImage(size: size)

        combinedImage.lockFocus()

        baseImage.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        let subIconSize = size.width * 0.4
        let padding: CGFloat = size.width * 0

        let subIconRect = NSRect(
            x: size.width - subIconSize - padding,
            y: padding,
            width: subIconSize,
            height: subIconSize
        )

        subIcon.draw(
            in: subIconRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        combinedImage.unlockFocus()
        NSApplication.shared.applicationIconImage = combinedImage
    }
}

extension AppDelegate {
    /// Convenience constant for getting the intended window size/frame.
    static internal let frame = NSRect(x: 0, y: 0, width: 500, height: 360)
}
