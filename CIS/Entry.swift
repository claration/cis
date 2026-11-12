//
//  stupiddiskimageinstallerApp.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

import AppKit

@main struct __ {
    static func main() {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

