import Foundation
import SwiftyStoreKit

public protocol IAPProtocol: CaseIterable {
    var productID: String { get }
    var price: Float { get }
    var type: IAPSubscriptionType { get }
}

public enum IAPSubscriptionType: Hashable {
    case autoRenewable
    case nonRenewing(validDuration: TimeInterval)
}

extension IAPSubscriptionType {
    func swiftyStoreKitValue() -> SubscriptionType {
        switch self {
        case .autoRenewable:
            return .autoRenewable
        case .nonRenewing(let validDuration):
            return .nonRenewing(validDuration: validDuration)
        }
    }
}
