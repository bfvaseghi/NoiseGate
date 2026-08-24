import Darwin
import Foundation

/// App-group persistence shared by the apps, extensions, and widgets.
///
/// UserDefaults does not make a read-modify-write sequence atomic across
/// processes. A process lock plus an app-group file lock prevents a monitor
/// callback, widget read, and foreground save from overwriting one another.
final class SharedStore {
    static let shared = SharedStore()

    private let defaults: UserDefaults
    private let lockFileURL: URL?
    private let processLock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Opened once and reused. Re-opening per access cost an open/close
    /// syscall pair on paths as hot as widget timeline reads and the Mac's
    /// five-second tick. Advisory `lockf` locks are owned per process and
    /// `processLock` already serialises callers within this process, so a
    /// single shared descriptor is both correct and cheaper. Only ever
    /// touched while `processLock` is held.
    private var cachedDescriptor: Int32?

    init(
        defaults: UserDefaults = AppGroup.defaults,
        lockFileURL: URL? = AppGroup.containerURL?
            .appendingPathComponent("noisegate.shared-store.lock")
    ) {
        self.defaults = defaults
        self.lockFileURL = lockFileURL
    }

    deinit {
        if let cachedDescriptor, cachedDescriptor >= 0 {
            Darwin.close(cachedDescriptor)
        }
    }

    func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        withExclusiveAccess { loadUnlocked(type, forKey: key) }
    }

    func save<T: Encodable>(_ value: T, forKey key: String) {
        withExclusiveAccess { saveUnlocked(value, forKey: key) }
    }

    func update<T: Codable>(
        _ type: T.Type,
        forKey key: String,
        default defaultValue: @autoclosure () -> T,
        _ update: (inout T) -> Void
    ) -> T {
        withExclusiveAccess {
            var value = loadUnlocked(type, forKey: key) ?? defaultValue()
            update(&value)
            saveUnlocked(value, forKey: key)
            return value
        }
    }

    func stringArray(forKey key: String) -> [String]? {
        withExclusiveAccess { defaults.stringArray(forKey: key) }
    }

    func saveStringArray(_ value: [String], forKey key: String) {
        withExclusiveAccess { defaults.set(value, forKey: key) }
    }

    func bool(forKey key: String) -> Bool {
        withExclusiveAccess { defaults.bool(forKey: key) }
    }

    func saveBool(_ value: Bool, forKey key: String) {
        withExclusiveAccess { defaults.set(value, forKey: key) }
    }

    func updateStringSet(forKey key: String, _ update: (inout Set<String>) -> Void) -> Set<String> {
        withExclusiveAccess {
            var value = Set(defaults.stringArray(forKey: key) ?? [])
            update(&value)
            defaults.set(value.sorted(), forKey: key)
            return value
        }
    }

    func removeValue(forKey key: String) {
        withExclusiveAccess { defaults.removeObject(forKey: key) }
    }

    private func loadUnlocked<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func saveUnlocked<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func withExclusiveAccess<T>(_ body: () -> T) -> T {
        processLock.lock()
        let descriptor = openLockFileIfNeeded()
        let hasFileLock = descriptor >= 0 && acquireFileLock(descriptor)
        defaults.synchronize()

        defer {
            defaults.synchronize()
            if hasFileLock {
                _ = Darwin.lockf(descriptor, F_ULOCK, 0)
            }
            processLock.unlock()
        }
        return body()
    }

    /// Resolves the shared descriptor, opening it on first use. `-1` is cached
    /// too, so a container that cannot be opened degrades to the process lock
    /// alone instead of retrying the syscall on every access.
    /// Must be called with `processLock` held.
    private func openLockFileIfNeeded() -> Int32 {
        if let cachedDescriptor { return cachedDescriptor }
        guard let lockFileURL else {
            cachedDescriptor = -1
            return -1
        }
        let descriptor = Darwin.open(
            lockFileURL.path,
            O_CREAT | O_RDWR | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        cachedDescriptor = descriptor
        return descriptor
    }

    private func acquireFileLock(_ descriptor: Int32) -> Bool {
        while true {
            if Darwin.lockf(descriptor, F_LOCK, 0) == 0 {
                return true
            }
            if errno != EINTR {
                return false
            }
        }
    }
}
