import Foundation

extension UserDefaults {

    private static let subscriptionStatusKey = "subscriptionStatus"

    /// Persists and restores `SubscriptionStatus` using JSON coding.
    ///
    /// Returns `.inactive` when no value has been stored yet or when decoding fails,
    /// which is the safe default for new installs or data migrations.
    var subscriptionStatus: SubscriptionStatus {
        get {
            guard let data = data(forKey: Self.subscriptionStatusKey),
                  let status = try? JSONDecoder().decode(SubscriptionStatus.self, from: data) else {
                return .inactive
            }
            return status
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, forKey: Self.subscriptionStatusKey)
            }
        }
    }
}
