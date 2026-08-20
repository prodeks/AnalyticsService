import Foundation

public protocol IAPProtocol: CaseIterable {
    var productID: String { get }
    var price: Float { get }
    var type: IAPSubscriptionType { get }
    var weekCount: Int { get }
}

public enum IAPSubscriptionType: Hashable {
    case autoRenewable
    case nonRenewing(validDuration: TimeInterval)
}

public extension IAPProtocol {
    var isLifetime: Bool {
        if case .nonRenewing = type {
            return true
        }
        return productID.isLifetimeProductID
    }
}

extension String {
    var isLifetimeProductID: Bool {
        localizedCaseInsensitiveContains("lifetime")
    }
}
