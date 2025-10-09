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
