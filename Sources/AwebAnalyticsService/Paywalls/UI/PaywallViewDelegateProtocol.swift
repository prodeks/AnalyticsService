import Foundation

public protocol PaywallViewDelegateProtocol: AnyObject {
    func restore()
    func purchase(_ iap: any IAPProtocol)
    
    func termsTap(_ item: URLConvertable)
    func privacyPolicyTap(_ item: URLConvertable)
    
    func dismiss()
    func navigate(to placement: PaywallPlacementProtocol)
    
    func pricingData(_ iap: any IAPProtocol) -> PricingData?

    /// Presentation metadata for host-app tap events. `nil` when the paywall
    /// was not shown through `PaywallController` (e.g. debug hosts).
    var paywallAnalyticsContext: PaywallAnalyticsContext? { get }
}

public extension PaywallViewDelegateProtocol {
    var paywallAnalyticsContext: PaywallAnalyticsContext? { nil }
}
