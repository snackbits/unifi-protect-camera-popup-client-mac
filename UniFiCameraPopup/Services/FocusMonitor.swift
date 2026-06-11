import Foundation

/// Watches the macOS Focus / Do Not Disturb database and fires a callback the
/// moment the state changes, so the UI reacts instantly instead of waiting for
/// the periodic poll.
///
/// macOS atomically replaces `Assertions.json` on every toggle, so we watch the
/// containing directory (which is stable) rather than the file itself. Opening
/// the directory requires Full Disk Access; without it `start()` is a no-op and
/// callers should keep their polling fallback.
final class FocusMonitor {
    private let directory: String
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.snackbits.unificamerapopup.focus-monitor", qos: .utility)

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var debounceItem: DispatchWorkItem?

    /// - Parameter onChange: invoked on the main queue, coalesced to avoid bursts.
    init(
        directory: String = "\(NSHomeDirectory())/Library/DoNotDisturb/DB",
        onChange: @escaping () -> Void
    ) {
        self.directory = directory
        self.onChange = onChange
    }

    /// Returns `true` if the watcher was armed (Full Disk Access available).
    @discardableResult
    func start() -> Bool {
        stop()

        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else { return false }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleNotify()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        self.source = source
        source.resume()
        return true
    }

    func stop() {
        debounceItem?.cancel()
        debounceItem = nil
        source?.cancel()
        source = nil
    }

    /// Coalesce rapid bursts (the system may rewrite the file several times for
    /// a single toggle) into one main-queue callback.
    private func scheduleNotify() {
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        DispatchQueue.main.async { [weak self] in
            self?.debounceItem?.cancel()
            self?.debounceItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
        }
    }

    deinit {
        source?.cancel()
    }
}
