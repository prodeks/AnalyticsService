import Combine
import Foundation

final class SubscriptionStatusStore {

    private let relay = CurrentValueSubject<SubscriptionStatus, Never>(UserDefaults.standard.subscriptionStatus)

    var current: SubscriptionStatus {
        get { UserDefaults.standard.subscriptionStatus }
        set {
            UserDefaults.standard.subscriptionStatus = newValue
            relay.send(newValue)
        }
    }

    var stream: AnyPublisher<SubscriptionStatus, Never> {
        relay.eraseToAnyPublisher()
    }
}
