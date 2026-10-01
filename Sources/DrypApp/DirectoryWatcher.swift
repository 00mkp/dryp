import Foundation

/// Notices changes in ~/.config/dryp — typically a `dryp` command — without polling. Watches the directory,
/// not the file: atomic writes replace the file, and a vnode source can only watch something that exists.
final class DirectoryWatcher {
    private let dir: URL
    private let onChange: () -> Void
    private let log: (String) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending = false

    init(dir: URL, log: @escaping (String) -> Void, onChange: @escaping () -> Void) {
        self.dir = dir
        self.log = log
        self.onChange = onChange
        arm()
    }

    private func arm() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else {
            log("watcher: cannot open \(dir.path)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            // The directory itself was removed or moved (e.g. by uninstall): re-arm on a fresh one.
            if !src.data.intersection([.delete, .rename]).isEmpty {
                src.cancel()
                self.arm()
            }
            self.fire()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    /// One atomic write produces several events; collapse them into one call.
    private func fire() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pending = false
            self?.onChange()
        }
    }
}
