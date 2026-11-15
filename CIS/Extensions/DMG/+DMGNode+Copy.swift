//
//  +DMGNode+Copy.swift
//  CIS
//
//  Created by samsam on 11/15/26.
//

import Foundation
internal import class DMG.DMGNode
internal import protocol DMG.DMGVolume

extension DMGNode {

    /// Copies a node to a specified directory.
    internal func copy(
        to url: URL,
        from volume: any DMGVolume,
        onProgress: @escaping (String) async -> Void
    ) async throws {
        try await Task.detached(priority: .utility) {
            let fm = FileManager.default

            switch self.kind {
            case .directory:
                await onProgress("Extract: \(self.name)")

                try fm.createDirectory(
                    at: url, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o755]
                )

                let children = try volume.children(of: self)

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for child in children {
                        group.addTask {
                            let childURL = await url.appending(
                                path: try child.name.diskSafeName(),
                                directoryHint: child.kind == .directory ? .isDirectory : .notDirectory
                            )
                            try await child.copy(to: childURL, from: volume, onProgress: onProgress)
                        }
                    }
                    try await group.waitForAll()
                }

                try await fm.setAttributes(self.attributes(), ofItemAtPath: url.path)
            case .symlink:
                let data = try volume.readData(of: self, offset: 0, length: 4096)
                let target = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\0", with: "")
                guard !target.isEmpty else {
                    throw DMGError.invalidSymlink(self.name)
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

                if self.size > 0 {
                    _ = ftruncate(fd, off_t(self.size))
                }
                _ = fcntl(fd, F_NOCACHE, 1)

                var offset: UInt64 = 0
                let chunkSize = 4 << 20 // 4 MB chunks

                while offset < self.size {
                    try autoreleasepool { // keeps memory flat for large files
                        let length = Int(min(UInt64(chunkSize), self.size - offset))
                        let chunk = try volume.readData(of: self, offset: offset, length: UInt(length))
                        if chunk.isEmpty { throw DMGError.shortRead(self.name) }

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

                try await fm.setAttributes(self.attributes(), ofItemAtPath: url.path)
            @unknown default:
                break
            }
        }.value
    }

    /// Attributes / permissions for a node.
    private func attributes() -> [FileAttributeKey: Any] {
        var mode = Int(self.permissions) & 0o777
        if mode == 0 {
            mode = self.kind == .directory ? 0o755 : 0o644
        }

        var attributes: [FileAttributeKey: Any] = [.posixPermissions: mode]
        if let date = self.modificationDate {
            attributes[.modificationDate] = date
        }

        return attributes
    }
}
