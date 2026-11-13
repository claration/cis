//
//  +NSDevice.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import class Foundation.ProcessInfo
internal import class Foundation.FileManager
internal import class Foundation.NSNumber

extension ProcessInfo {
    /// The operating systems remaining space, in formatted bytes (i.e. 236 GB).
    internal func remainingSpace() -> String? {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/")

        if let freeSizeNumber = attrs?[.systemFreeSize] as? NSNumber {
            return freeSizeNumber.int64Value.formattedBytes()
        }

        return nil
    }

    /// The operating systems marketing model using `libMobileGestalt`.
    internal var marketingModel: String {
        MGCopyAnswer(kMGPhysicalHardwareNameString)?.takeUnretainedValue() as? String ?? "Unknown"
    }
}
