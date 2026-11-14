//
//  +BinaryInteger.swift
//  CIS
//
//  Created by samsam on 11/12/26.
//

import class Foundation.ByteCountFormatter

extension BinaryInteger {
    /// BinaryInteger in formatted bytes (i.e. 45.5 GB or 285.2 MB).
    internal func formattedBytes(
        allowedUnits: ByteCountFormatter.Units = [.useAll],
        countStyle: ByteCountFormatter.CountStyle = .file
    ) -> String {
        let int64Bytes = Int64(clamping: self)
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = allowedUnits
        formatter.countStyle = countStyle
        return formatter.string(fromByteCount: int64Bytes)
    }
}
