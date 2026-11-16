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
    internal let volume: any DMGVolume
    internal let filePath: URL

    internal let name: String
    internal let virtualSize: UInt64
    internal let nodes: [DMGNode]
    internal var icon: NSImage? = nil
    internal var color: NSColor = .systemGray
    internal var license: DMGLicense? = nil

    internal var nodesToInstall: [DMGNode] = []
    internal var destinationPath = URL(filePath: "/Applications")

    internal let isPkg: Bool

    // MARK: Setup

    internal init(for filePath: URL) throws {
        let parser = try DMGParser(contentsOfFile: filePath.path)
        let volume = try DMGVolumeLoader.open(parser: parser)

        self.volume = volume
        self.filePath = filePath

        self.name = volume.volumeName
        self.virtualSize = parser.virtualSize

        var installableNodes = try volume.nodes(kind: .directory, suffix: ".app")

        if let icon = volume.volumeIcon() {
            self.icon = icon
        } else if let icon = installableNodes.first?.nodeIcon(in: volume) {
            self.icon = icon
        }

        if let color = self.icon?.primaryColor {
            self.color = color
        }

        if
            let licenses = try? parser.licenseAgreements(),
            !licenses.isEmpty
        {
            self.license = licenses.first
        } else if let license = volume.licenseFile() {
            self.license = license
        }

        if installableNodes.isEmpty {
            installableNodes = try volume.nodes(kind: .file, suffix: ".pkg")

            print(installableNodes)

            print("installableNodes was empty, but checking for PKG")

            if installableNodes.isEmpty {
                throw DMGError.appsUnavailable(self.name)
            } else {
                print("PKGS EXIST!")
                self.isPkg = true
            }
        } else {
            self.isPkg = false
        }

        self.nodes = installableNodes
        self.nodesToInstall = installableNodes
    }

    internal func installNodes(
        onProgress: @escaping (String) async -> Void
    ) async throws {
        var isDirectory: ObjCBool = false

        if
            !FileManager.default.fileExists(
                atPath: destinationPath.path,
                isDirectory: &isDirectory
            )
        {
            try FileManager.default.createDirectory(
                at: destinationPath,
                withIntermediateDirectories: true
            )
        } else if !isDirectory.boolValue {
            throw DMGError.destinationNotDirectory(destinationPath)
        }

        for node in nodesToInstall {
            guard
                node.kind == .directory,
                node.name.lowercased().hasSuffix(".app")
            else {
                await onProgress("Error: Not an app!")
                throw DMGError.notAnApp(node.name)
            }

            let target = destinationPath.appending(
                path: try node.name.diskSafeName(),
                directoryHint: .isDirectory
            )

            let staging = destinationPath.appending(
                path: ".installing-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )

            do {
                try await node.copy(
                    to: staging,
                    from: volume,
                    onProgress: onProgress
                )

                if FileManager.default.fileExists(atPath: target.path) {
                    _ = try FileManager.default.replaceItemAt(target, withItemAt: staging)
                } else {
                    try FileManager.default.moveItem(at: staging, to: target)
                }
            } catch {
                try? FileManager.default.removeItem(at: staging)
                await onProgress("Error: \(error.localizedDescription)")
                throw error
            }
        }
    }

    internal func openNodes() async throws {
        guard isPkg else {
            throw DMGError.notAPkg
        }

        for node in nodesToInstall {
            let tempPath = FileManager.default.temporaryDirectory.appending(
                path: ".pkg-\(try node.name.diskSafeName()).pkg"
            )

            try await node.copy(to: tempPath, from: volume, onProgress: { _ in })

            Process.runProcess(
                executable: "/usr/bin/open",
                arguments: ["-a", "Installer", tempPath.relativePath]
            )
        }
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
    case notAPkg

    internal var errorDescription: String? {
        switch self {
        case .destinationNotDirectory(let url): "\"\(url.path)\" is not a folder."
        case .notAnApp(let name):               "\"\(name)\" is not an .app bundle."
        case .unsafeName(let name):             "Refusing to copy item with unsafe name \"\(name)\"."
        case .invalidSymlink(let name):         "Could not read the target of symlink \"\(name)\"."
        case .shortRead(let name):              "Unexpected end of data while reading \"\(name)\"."
        case .appsUnavailable(let name):        "No applications are available for \"\(name)\"."
        case .notAPkg:                          "No PKG files available for installation."
        }
    }
}

