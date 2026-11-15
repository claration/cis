//
//  +DMGVolume.swift
//  CIS
//
//  Created by samsam on 11/15/26.
//

import Foundation
internal import class AppKit.NSImage
internal import class DMG.DMGNode
internal import class DMG.DMGLicense
internal import enum DMG.DMGNodeKind
internal import protocol DMG.DMGVolume

/// Helper for finding children.
internal func findChild(
    _ parent: DMGNode,
    kind: DMGNodeKind,
    named name: String,
    in volume: any DMGVolume
) -> DMGNode? {
    try? volume.children(of: parent).first {
        $0.kind == kind && $0.name.caseInsensitiveCompare(name) == .orderedSame
    }
}

extension DMGVolume {

    /// Returns a volume icon, if any.
    internal func volumeIcon() -> NSImage? {
        guard
            let iconNode = findChild(rootNode, kind: .file, named: ".volumeicon.icns", in: self),
            iconNode.size > 0,
            let iconData = try? readData(of: iconNode, offset: 0, length: UInt(iconNode.size))
        else {
            return nil
        }

        return NSImage(data: iconData)
    }

    /// Returns a distributed plain text license file, if any.
    ///
    /// Hex Field for example distributes a LICENSE.txt file with their DMG.
    internal func licenseFile() -> DMGLicense? {
        guard
            let node = findChild(rootNode, kind: .file, named: "LICENSE.txt", in: self),
            node.size > 0,
            let data = try? readData(
                of: node,
                offset: 0,
                length: UInt(Int(min(node.size, UInt64(2 << 20))))
            )
        else {
            return nil
        }

        return DMGLicense(regionCode: 0, textData: data, rtfData: nil, buttonData: nil)
    }
}



