import Foundation

public class PaywallEvent: EventProtocol {
    public var name: String {
        ""
    }
    public var params: [String: Any] {
        [:]
    }
    
    let paywallID: String
    
    public init(paywallID: String) {
        self.paywallID = paywallID
    }
}

public class PaywallOpenEvent: PaywallEvent {
    public override var name: String {
        "PaywallOpenEvent_\(paywallID)"
    }
}

public class PaywallClosedEvent: PaywallEvent {
    public override var name: String {
        "PaywallClosedEvent_\(paywallID)"
    }
}

public class PaywallCheckoutStartedEvent: PaywallEvent {
    public override var name: String {
        "paywall_checkout_initiated"
    }
}

public class PaywallCheckoutCancelledEvent: PaywallEvent {
    public override var name: String {
        "paywall_checkout_cancelled"
    }
}

public struct PurchaseFailedEvent: EventProtocol {
    public var name: String { "purchaseFailed" }
    
    let reason: String
    let productID: String
    let placement: String
    let errorDomain: String
    let errorCode: Int
    
    public var params: [String: Any] {
        [
            "reason": reason,
            "productID": productID,
            "placement": placement,
            "errorDomain": errorDomain,
            "errorCode": errorCode
        ]
    }
    
    public init(
        reason: String,
        productID: String,
        placement: String,
        errorDomain: String,
        errorCode: Int
    ) {
        self.reason = reason
        self.productID = productID
        self.placement = placement
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

public struct RestoreFailedEvent: EventProtocol {
    public var name: String { "restoreFailed" }
    
    let reason: String
    let errorDomain: String
    let errorCode: Int
    
    public var params: [String: Any] {
        [
            "reason": reason,
            "errorDomain": errorDomain,
            "errorCode": errorCode
        ]
    }
    
    public init(
        reason: String,
        errorDomain: String,
        errorCode: Int
    ) {
        self.reason = reason
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

public struct PaywallFetchErrorEvent: EventProtocol {
    public var name: String { "paywall_fetch_error" }
    let placement: String
    let errorDescription: String
    public var params: [String: Any] {
        ["placement": placement, "error": errorDescription]
    }
}

public struct OnboardingStartedEvent: EventProtocol {
    public var name: String {
        "Onboarding_Started"
    }
    public var params: [String : Any] {
        [:]
    }
    public init() {}
}
