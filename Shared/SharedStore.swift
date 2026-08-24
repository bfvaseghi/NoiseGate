import Darwin
import Foundation

/// App-group persistence shared by the apps, extensions, and widgets.
///
/// UserDefaults does not make a read-modify-write sequence atomic across
/// processes. A process lock plus an app-group `flock` prevents a monitor
/// callback, widget read, and foreground save from overwriting one another.
final class SharedStore {
    static let shared = SharedStore()

    private let defaults: UserDefaults
    private let lockFileURL: URL?
    private let processLock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = AppGroup.defaults,
        lockFileURL: URL? = AppGroup.containerURL?
            .appendingPathComponent("noisegate.shared-store.lock")
    ) {
        self.defaults = defaults
        self.lockFileURL = lockFileURL
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
        let descriptor = lockFileURL.map {
            Darwin.open($0.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        } ?? -1
        if descriptor >= 0 {
            _ = Darwin.flock(descriptor, LOCK_EX)
        }
        defaults.synchronize()

        defer {
            defaults.synchronize()
            if descriptor >= 0 {
                _ = Darwin.flock(descriptor, LOCK_UN)
                Darwin.close(descriptor)
            }
            processLock.unlock()
        }
        return body()
    }
}
