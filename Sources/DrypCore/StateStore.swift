import Foundation

public enum StoreError: Error, CustomStringConvertible {
    case lockFailed(String)
    public var description: String {
        switch self { case .lockFailed(let why): return "couldn't lock the state file: \(why)" }
    }
}

/// The requests file. Every write is a read-modify-write under an exclusive flock, written atomically.
public struct StateStore: Sendable {
    public enum ReadResult: Equatable { case ok(DrypState), missing, corrupt }

    public let paths: Paths

    public init(paths: Paths) { self.paths = paths }

    public func read() -> ReadResult {
        guard let data = try? Data(contentsOf: paths.stateFile) else { return .missing }
        guard let state = try? DrypJSON.decoder.decode(DrypState.self, from: data) else { return .corrupt }
        return .ok(state)
    }

    /// The current requests, or defaults when the file is missing or unreadable.
    public func current() -> DrypState {
        if case .ok(let s) = read() { return s }
        return DrypState()
    }

    @discardableResult
    public func update(_ body: (inout DrypState) throws -> Void) throws -> DrypState {
        try withLock {
            var state: DrypState
            switch read() {
            case .ok(let s): state = s
            case .missing: state = DrypState()
            case .corrupt: try quarantineLocked(); state = DrypState()
            }
            let before = state
            try body(&state)
            guard state != before else { return state }
            // Wall-clock milliseconds keep rev rising even if the file is deleted and recreated, so a stale
            // applied.rev can never look like an acknowledgement of a fresh request.
            state.rev = max(before.rev + 1, Int((Date().timeIntervalSince1970 * 1000).rounded(.down)))
            try DrypJSON.encoder.encode(state).write(to: paths.stateFile, options: .atomic)
            return state
        }
    }

    /// Clears each mode only if it still holds exactly the given session, so a request written between the
    /// agent's read and this write survives.
    @discardableResult
    public func clear(_ sessions: [Mode: Session]) throws -> DrypState {
        try update { s in
            for (mode, old) in sessions where s[mode] == old { s[mode] = nil }
        }
    }

    /// Moves an unreadable state.json aside to state.json.bad. Returns whether it did.
    public func quarantineCorrupt() throws -> Bool {
        try withLock {
            guard read() == .corrupt else { return false }
            try quarantineLocked()
            return true
        }
    }

    private func quarantineLocked() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: paths.badStateFile)
        try fm.moveItem(at: paths.stateFile, to: paths.badStateFile)
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: paths.configDir, withIntermediateDirectories: true)
        let fd = open(paths.lockFile.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw StoreError.lockFailed(String(cString: strerror(errno))) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw StoreError.lockFailed(String(cString: strerror(errno))) }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
