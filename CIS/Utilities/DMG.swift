//
//  DMG.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit
internal import class ColorCube.CCColorCube
internal import class DMG.DMGParser
internal import class DMG.DMGVolumeLoader
internal import class DMG.DMGNode
internal import class DMG.DMGLicense
internal import protocol DMG.DMGVolume

internal final class DMG {
    internal let name: String
    internal let path: URL
    internal var destinationFolderPath: URL = .init(filePath: "/Applications")
    internal let icon: NSImage?
    internal let color: NSColor?
    internal let virtualSize: UInt64
    internal let licenses: [DMGLicense]
    internal var nodesToInstall: [DMGNode] = []

    private let volume: any DMGVolume

    // MARK: Setup

    internal init(path: URL) throws {
        let parser = try DMGParser(contentsOfFile: path.path)
        let volume = try DMGVolumeLoader.open(parser: parser)

        self.path = path
        self.volume = volume
        self.name = volume.volumeName

        if
            let agreements = try? parser.licenseAgreements(),
            !agreements.isEmpty
        {
            self.licenses = agreements
        } else if let singleLicense = Self.findLicenseFile(in: volume) {
            self.licenses = [singleLicense]
        } else {
            self.licenses = []
        }

        self.icon = Self.findIcon(in: volume)
        self.virtualSize = parser.virtualSize

        if let icon = self.icon {
            let cc = CCColorCube()
            // COLORCUBE GIVES THE UGLIEST COLORS EVER
            if let c = cc.extractColors(
                from: icon,
                flags: [.orderByBrightness, .onlyDarkColors]
            )?.first {
                self.color = c
            } else {
                self.color = nil
            }
        } else {
            self.color = nil
        }

        // finds available app instances to install
        self.nodesToInstall = try self.lookup()
        // nothing to install
        if self.nodesToInstall.isEmpty {
            throw DMGError.appsUnavailable(self.name)
        }
    }

    // MARK: Utils

    internal func lookup() throws -> [DMGNode] {
        try volume.children(of: volume.rootNode).filter {
            $0.kind == .directory && $0.name.lowercased().hasSuffix(".app")
        }
    }

    @discardableResult
    internal func install(
        _ apps: [DMGNode],
        onProgress: @escaping (String) async -> Void
    ) async throws -> [URL] {
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        if !fm.fileExists(atPath: destinationFolderPath.path, isDirectory: &isDirectory) {
            try fm.createDirectory(at: destinationFolderPath, withIntermediateDirectories: true)
        } else if !isDirectory.boolValue {
            throw DMGError.destinationNotDirectory(destinationFolderPath)
        }

        var installed: [URL] = []
        for app in apps {
            guard
                app.kind == .directory,
                app.name.lowercased().hasSuffix(".app")
            else {
                await onProgress("Error: Not an app!")
                throw DMGError.notAnApp(app.name)
            }

            let appName = try Self.diskName(app.name)
            let target = destinationFolderPath.appending(path: appName, directoryHint: .isDirectory)
            let staging = destinationFolderPath.appending(
                path: ".\(appName).installing-\(UUID().uuidString)", directoryHint: .isDirectory)

            do {
                try await copy(app, to: staging, onProgress: onProgress)
                if fm.fileExists(atPath: target.path) {
                    _ = try fm.replaceItemAt(target, withItemAt: staging)
                } else {
                    try fm.moveItem(at: staging, to: target)
                }
            } catch {
                try? fm.removeItem(at: staging)
                await onProgress("Error: \(error.localizedDescription)")
                throw error
            }
            installed.append(target)
        }
        return installed
    }

    // MARK: - Copying

    private func copy(
        _ node: DMGNode,
        to url: URL,
        onProgress: @escaping (String) async -> Void
    ) async throws {
        // GIGA
        let currentVolume = self.volume

        try await Task.detached(priority: .utility) {
            let fm = FileManager.default

            switch node.kind {
            case .directory:
                await onProgress("Extract: \(node.name)")

                try fm.createDirectory(
                    at: url, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o755]
                )

                let children = try currentVolume.children(of: node)

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for child in children {
                        group.addTask {
                            let childURL = await url.appending(
                                path: try Self.diskName(child.name),
                                directoryHint: child.kind == .directory ? .isDirectory : .notDirectory
                            )
                            try await self.copy(child, to: childURL, onProgress: onProgress)
                        }
                    }
                    try await group.waitForAll()
                }

                try await fm.setAttributes(Self.attributes(for: node), ofItemAtPath: url.path)
            case .symlink:
                let data = try currentVolume.readData(of: node, offset: 0, length: 4096)
                let target = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\0", with: "")
                guard !target.isEmpty else {
                    throw DMGError.invalidSymlink(node.name)
                }
                try fm.createSymbolicLink(atPath: url.path, withDestinationPath: target)

            case .file:
                let path = url.path
                let fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o600)
                guard fd >= 0 else {
                    throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
                }

                var closed = false
                defer {
                    if !closed { close(fd) }
                }

                if node.size > 0 {
                    _ = ftruncate(fd, off_t(node.size))
                }
                _ = fcntl(fd, F_NOCACHE, 1)

                var offset: UInt64 = 0
                let chunkSize = 4 << 20 // 4 MB chunks

                while offset < node.size {
                    try autoreleasepool { // keeps memory flat for large files
                        let length = Int(min(UInt64(chunkSize), node.size - offset))
                        let chunk = try currentVolume.readData(of: node, offset: offset, length: UInt(length))
                        if chunk.isEmpty { throw DMGError.shortRead(node.name) }

                        try chunk.withUnsafeBytes { rawBuffer in
                            guard let baseAddress = rawBuffer.baseAddress else { return }
                            var totalWritten = 0
                            let bytesToWrite = chunk.count

                            while totalWritten < bytesToWrite {
                                let written = write(fd, baseAddress.advanced(by: totalWritten), bytesToWrite - totalWritten)
                                if written < 0 {
                                    throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
                                }
                                totalWritten += Int(written)
                            }
                        }

                        offset += UInt64(chunk.count)
                    }
                }

                close(fd)
                closed = true

                try await fm.setAttributes(Self.attributes(for: node), ofItemAtPath: url.path)
            @unknown default:
                break
            }
        }.value
    }

    private static func attributes(for node: DMGNode) -> [FileAttributeKey: Any] {
        var mode = Int(node.permissions) & 0o777
        if mode == 0 {
            mode = node.kind == .directory ? 0o755 : 0o644
        }

        var attributes: [FileAttributeKey: Any] = [.posixPermissions: mode]
        if let date = node.modificationDate {
            attributes[.modificationDate] = date
        }

        return attributes
    }

    // HFS+ shows ':' as '/', so on disk we use ':' the way Finder does
    // also ignores some path traversal stuffs
    private static func diskName(_ name: String) throws -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: ":")
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." || cleaned.contains("\0") {
            throw DMGError.unsafeName(name)
        }

        return cleaned
    }
}

// MARK: - file finders

extension DMG {
    private static func findLicenseFile(in volume: any DMGVolume) -> DMGLicense? {
        guard let children = try? volume.children(of: volume.rootNode) else {
            return nil
        }

        let texts = children.filter {
            $0.kind == .file && $0.name.lowercased().hasSuffix(".txt")
        }

        let preferred = texts.first { node in
            let lowered = node.name.lowercased()
            return ["license", "licence", "eula", "copying"].contains {
                lowered.contains($0)
            }
        }

        let maxLicenseBytes = 2 << 20

        guard
            let node = preferred ?? texts.first,
            node.size > 0,
            let data = try? volume.readData(
                of: node,
                offset: 0,
                length: UInt(Int(min(node.size, UInt64(maxLicenseBytes))))
            )
        else {
            return nil
        }

        return DMGLicense(regionCode: 0, textData: data, rtfData: nil, buttonData: nil)
    }

    // jesus christ
    private static func findIcon(in volume: any DMGVolume) -> NSImage? {
        if
            let rootChildren = try? volume.children(of: volume.rootNode),
            let volumeIconNode = rootChildren.first(where: { $0.kind == .file && $0.name.lowercased() == ".volumeicon.icns" }),
            volumeIconNode.size > 0,
            let iconData = try? volume.readData(of: volumeIconNode, offset: 0, length: UInt(volumeIconNode.size)),
            let image = NSImage(data: iconData)
        {
            return image
        }

        guard
            let rootChildren = try? volume.children(of: volume.rootNode),
            let appNode = rootChildren.first(where: { $0.kind == .directory && $0.name.lowercased().hasSuffix(".app") }),
            let appChildren = try? volume.children(of: appNode),
            let contentsNode = appChildren.first(where: { $0.kind == .directory && $0.name.lowercased() == "contents" }),
            let contentsChildren = try? volume.children(of: contentsNode),
            let infoPlistNode = contentsChildren.first(where: { $0.kind == .file && $0.name.lowercased() == "info.plist" }),
            infoPlistNode.size > 0,
            let plistData = try? volume.readData(of: infoPlistNode, offset: 0, length: UInt(infoPlistNode.size)),
            let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
            let rawIconName = (plist["CFBundleIconFile"] as? String) ?? (plist["CFBundleIconName"] as? String)
        else {
            return nil
        }

        let icnsFileName = rawIconName.lowercased().hasSuffix(".icns") ? rawIconName : rawIconName + ".icns"

        guard
            let resourcesNode = contentsChildren.first(where: { $0.kind == .directory && $0.name.lowercased() == "resources" }),
            let resourceChildren = try? volume.children(of: resourcesNode),
            let icnsNode = resourceChildren.first(where: { $0.kind == .file && $0.name.lowercased() == icnsFileName.lowercased() }),
            icnsNode.size > 0,
            let icnsData = try? volume.readData(of: icnsNode, offset: 0, length: UInt(icnsNode.size))
        else {
            return nil
        }

        return NSImage(data: icnsData)
    }
}

// MARK: - DMGError

internal enum DMGError: LocalizedError {
    case destinationNotDirectory(URL)
    case notAnApp(String)
    case unsafeName(String)
    case invalidSymlink(String)
    case shortRead(String)
    case appsUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .destinationNotDirectory(let url): "\"\(url.path)\" is not a folder."
        case .notAnApp(let name):               "\"\(name)\" is not an .app bundle."
        case .unsafeName(let name):             "Refusing to copy item with unsafe name \"\(name)\"."
        case .invalidSymlink(let name):         "Could not read the target of symlink \"\(name)\"."
        case .shortRead(let name):              "Unexpected end of data while reading \"\(name)\"."
        case .appsUnavailable(let name):        "No applications are available for \"\(name)\"."
        }
    }
}

