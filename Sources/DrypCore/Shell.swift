import Foundation

public enum Shell {
    public struct Result: Equatable, Sendable {
        public var status: Int32
        public var output: String

        public init(status: Int32, output: String) {
            self.status = status
            self.output = output
        }
    }

    /// Runs a tool with stdout+stderr captured and no stdin. 127 = couldn't launch, 124 = timed out.
    @discardableResult
    public static func run(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return Result(status: 127, output: error.localizedDescription) }

        var data = Data()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return Result(status: 124, output: "timed out after \(timeout)s")
        }
        readDone.wait()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// Runs a tool attached to this terminal (sudo prompts, git, install.sh). Returns its exit status.
    public static func interactive(_ path: String, _ args: [String], environment: [String: String] = [:]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        }
        do { try process.run() } catch { return 127 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    public static func liveSleepDisabled() -> Bool? {
        Pmset.sleepDisabled(fromLive: run(PmsetCommand.pmset, PmsetCommand.readLive).output)
    }
}
