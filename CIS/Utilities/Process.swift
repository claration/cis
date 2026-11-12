//
//  Process.swift
//  CIS
//
//  Created by samsam on 11/12/26.
//

import Foundation

/// Helper function for launching processes.
@discardableResult
internal func runProcess(
    executable: String,
    arguments: [String]
) -> (success: Bool, output: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return (task.terminationStatus == 0, output.trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
        return (false, error.localizedDescription)
    }
}
