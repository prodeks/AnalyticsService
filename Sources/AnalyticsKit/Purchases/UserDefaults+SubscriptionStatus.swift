import Foundation

extension UserDefaults {

    private static let subscriptionStatusKey = "subscriptionStatus"

    /// Persists and restores `SubscriptionStatus` using JSON coding.
    ///
    /// Returns `.inactive` when no value has been stored yet or when decoding fails,
    /// which is the safe default for new installs or data migrations.
    var subscriptionStatus: SubscriptionStatus {
        get {
            guard let data = data(forKey: Self.subscriptionStatusKey) else {
                return .inactive
            }
            do {
                return try JSONDecoder().decode(SubscriptionStatus.self, from: data)
            } catch {
                Log.printLog(
                    l: .error,
                    str: "Failed to decode subscription status: \(error.localizedDescription)"
                )
                return .inactive
            }
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                set(data, forKey: Self.subscriptionStatusKey)
            } catch {
                Log.printLog(
                    l: .error,
                    str: "Failed to encode subscription status: \(error.localizedDescription)"
                )
            }
        }
    }
}
