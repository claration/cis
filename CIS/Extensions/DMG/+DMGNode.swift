//
//  +DMGNode.swift
//  CIS
//
//  Created by samsam on 11/15/26.
//

import Foundation
internal import class AppKit.NSImage
internal import class DMG.DMGNode
internal import class DMG.DMGLicense
internal import protocol DMG.DMGVolume

extension DMGNode {

    /// Returns an icon to an .app node, if any.
    internal func nodeIcon(in volume: any DMGVolume) -> NSImage? {
        guard
            let rootChildren = try? volume.children(of: volume.rootNode),
            let appNode = rootChildren.first(where: { $0.kind == .directory && $0.name.lowercased().hasSuffix(".app") }),
            let contentsNode = findChild(appNode, kind: .directory, named: "Contents", in: volume),
            let infoPlistNode = findChild(contentsNode, kind: .file, named: "Info.plist", in: volume),
            infoPlistNode.size > 0,
            let plistData = try? volume.readData(of: infoPlistNode, offset: 0, length: UInt(infoPlistNode.size)),
            let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
            let rawIconName = (plist["CFBundleIconFile"] as? String) ?? (plist["CFBundleIconName"] as? String)
        else {
            return nil
        }

        let icnsFileName = rawIconName.lowercased().hasSuffix(".icns") ? rawIconName : rawIconName + ".icns"

        guard
            let resourcesNode = findChild(contentsNode, kind: .directory, named: "Resources", in: volume),
            let icnsNode = findChild(resourcesNode, kind: .file, named: icnsFileName, in: volume),
            icnsNode.size > 0,
            let icnsData = try? volume.readData(of: icnsNode, offset: 0, length: UInt(icnsNode.size))
        else {
            return nil
        }

        return NSImage(data: icnsData)
    }
}
