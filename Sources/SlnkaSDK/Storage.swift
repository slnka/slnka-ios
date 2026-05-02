import Foundation

/// Persistence layer using UserDefaults for the SLNK SDK.
/// Stores anonymous ID, user ID, deferred deep link flag, and failed events.
final class SlnkaStorage {

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "ma.slnka.sdk.storage", attributes: .concurrent)

    // MARK: - Keys

    private enum Keys {
        static let anonymousId = "__slnka_anonymous_id"
        static let userId = "__slnka_user_id"
        static let deferredResolved = "__slnka_deferred_resolved"
        static let failedEvents = "__slnka_failed_events"
        static let sessionId = "__slnka_session_id"
        static let sessionStartTime = "__slnka_session_start"
        static let userTraits = "__slnka_user_traits"
        static let consentGranted = "__slnka_consent_granted"
        static let firstLaunch = "__slnka_first_launch"
        static let installTimestamp = "__slnka_install_timestamp"
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Anonymous ID

    /// Returns the stored anonymous ID, or generates and stores a new one.
    func getOrCreateAnonymousId() -> String {
        if let existing = getString(Keys.anonymousId) {
            return existing
        }
        let newId = "anon_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
        setString(Keys.anonymousId, value: newId)
        return newId
    }

    /// Resets the anonymous ID to a new random value.
    func resetAnonymousId() -> String {
        let newId = "anon_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
        setString(Keys.anonymousId, value: newId)
        return newId
    }

    // MARK: - User ID

    func getUserId() -> String? {
        return getString(Keys.userId)
    }

    func setUserId(_ userId: String?) {
        setString(Keys.userId, value: userId)
    }

    // MARK: - User Traits

    func getUserTraits() -> [String: Any]? {
        return getDictionary(Keys.userTraits)
    }

    func setUserTraits(_ traits: [String: Any]?) {
        if let traits = traits {
            setDictionary(Keys.userTraits, value: traits)
        } else {
            remove(Keys.userTraits)
        }
    }

    // MARK: - Deferred Deep Link

    /// Returns true if the deferred deep link has already been resolved.
    func isDeferredResolved() -> Bool {
        return getBool(Keys.deferredResolved)
    }

    /// Marks the deferred deep link as resolved.
    func markDeferredResolved() {
        setBool(Keys.deferredResolved, value: true)
    }

    // MARK: - Consent

    /// Returns whether the user has granted consent for analytics tracking.
    func isConsentGranted() -> Bool {
        return getBool(Keys.consentGranted)
    }

    /// Sets the consent granted state.
    func setConsentGranted(_ granted: Bool) {
        setBool(Keys.consentGranted, value: granted)
    }

    // MARK: - Session

    func getSessionId() -> String? {
        return getString(Keys.sessionId)
    }

    func setSessionId(_ sessionId: String) {
        setString(Keys.sessionId, value: sessionId)
    }

    func getSessionStartTime() -> Date? {
        let interval = defaults.double(forKey: Keys.sessionStartTime)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    func setSessionStartTime(_ date: Date) {
        queue.async(flags: .barrier) { [defaults] in
            defaults.set(date.timeIntervalSince1970, forKey: Keys.sessionStartTime)
        }
    }

    // MARK: - Failed Events Queue

    /// Stores events that failed to send for later retry.
    func storeFailedEvents(_ events: [SlnkaEvent]) {
        queue.async(flags: .barrier) { [defaults] in
            do {
                let existing = self.loadFailedEventsSync()
                var combined = existing + events

                // Cap to prevent unbounded storage growth
                if combined.count > 1000 {
                    combined = Array(combined.suffix(1000))
                }

                let data = try JSONEncoder().encode(combined)
                defaults.set(data, forKey: Keys.failedEvents)
            } catch {
                // Silently fail; events will be lost rather than crash
            }
        }
    }

    /// Loads and removes stored failed events.
    func loadAndClearFailedEvents() -> [SlnkaEvent] {
        var result: [SlnkaEvent] = []
        queue.sync {
            result = self.loadFailedEventsSync()
        }
        queue.async(flags: .barrier) { [defaults] in
            defaults.removeObject(forKey: Keys.failedEvents)
        }
        return result
    }

    private func loadFailedEventsSync() -> [SlnkaEvent] {
        guard let data = defaults.data(forKey: Keys.failedEvents) else { return [] }
        do {
            return try JSONDecoder().decode([SlnkaEvent].self, from: data)
        } catch {
            return []
        }
    }

    // MARK: - Generic Key-Value (Feedback Fatigue)

    /// Returns the string value for the given key, or `nil` if not set.
    func getString(forKey key: String) -> String? {
        return getString(key)
    }

    /// Stores a string value for the given key.
    func setString(_ value: String, forKey key: String) {
        setString(key, value: value)
    }

    /// Returns the integer value for the given key (0 if not set).
    func getInt(forKey key: String) -> Int {
        queue.sync { defaults.integer(forKey: key) }
    }

    /// Stores an integer value for the given key.
    func setInt(_ value: Int, forKey key: String) {
        queue.async(flags: .barrier) { [defaults] in
            defaults.set(value, forKey: key)
        }
    }

    // MARK: - Clear All

    /// Clears all SLNK-related data from UserDefaults.
    func clearAll() {
        queue.async(flags: .barrier) { [defaults] in
            defaults.removeObject(forKey: Keys.anonymousId)
            defaults.removeObject(forKey: Keys.userId)
            defaults.removeObject(forKey: Keys.deferredResolved)
            defaults.removeObject(forKey: Keys.failedEvents)
            defaults.removeObject(forKey: Keys.sessionId)
            defaults.removeObject(forKey: Keys.sessionStartTime)
            defaults.removeObject(forKey: Keys.userTraits)
            defaults.removeObject(forKey: Keys.consentGranted)
        }
    }

    // MARK: - Private Helpers

    private func getString(_ key: String) -> String? {
        queue.sync { defaults.string(forKey: key) }
    }

    private func setString(_ key: String, value: String?) {
        queue.async(flags: .barrier) { [defaults] in
            if let value = value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func getBool(_ key: String) -> Bool {
        queue.sync { defaults.bool(forKey: key) }
    }

    private func setBool(_ key: String, value: Bool) {
        queue.async(flags: .barrier) { [defaults] in
            defaults.set(value, forKey: key)
        }
    }

    private func getDictionary(_ key: String) -> [String: Any]? {
        queue.sync { defaults.dictionary(forKey: key) }
    }

    private func setDictionary(_ key: String, value: [String: Any]) {
        queue.async(flags: .barrier) { [defaults] in
            defaults.set(value, forKey: key)
        }
    }

    private func remove(_ key: String) {
        queue.async(flags: .barrier) { [defaults] in
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - First Launch Detection

    /// Returns true the first time it is called for a given install, false on subsequent calls.
    /// Mirrors Android Storage.kt isFirstLaunch() behavior.
    func isFirstLaunch() -> Bool {
        let alreadyLaunched = queue.sync { defaults.bool(forKey: Keys.firstLaunch) }
        if !alreadyLaunched {
            queue.async(flags: .barrier) { [defaults] in
                defaults.set(true, forKey: Keys.firstLaunch)
                defaults.set(Date().timeIntervalSince1970, forKey: Keys.installTimestamp)
            }
            return true
        }
        return false
    }

    /// Returns the install timestamp (seconds since epoch), or nil if SDK never tracked first launch.
    func getInstallTimestamp() -> TimeInterval? {
        return queue.sync {
            let v = defaults.double(forKey: Keys.installTimestamp)
            return v > 0 ? v : nil
        }
    }
}
