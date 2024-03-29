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

public struct OnboardingStartedEvent: EventProtocol {
    public var name: String {
        "Onboarding_Started"
    }
    public var params: [String : Any] {
        [:]
    }
}
