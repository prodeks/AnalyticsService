import Foundation

public protocol PaywallViewDelegateProtocol: AnyObject {
    func restore()
    func purchase(_ iap: any IAPProtocol)
    
    func termsTap(_ item: URLConvertable)
    func privacyPolicyTap(_ item: URLConvertable)
    
    func dismiss()
    func navigate(to placement: any PaywallPlacementProtocol)
    
    func pricingData(_ iap: any IAPProtocol) -> PricingData?

    /// Presentation metadata for host-app tap events. `nil` when the paywall
    /// was not shown through `PaywallController` (e.g. debug hosts).
    var paywallAnalyticsContext: PaywallAnalyticsContext? { get }

    /// Host paywalls call this when the user picks a product row. `PaywallController`
    /// logs `PayWall_Lifetime_button_tap` when the selection is a Lifetime SKU.
    func didSelectProduct(_ iap: any IAPProtocol, previous: (any IAPProtocol)?)
}

public extension PaywallViewDelegateProtocol {
    var paywallAnalyticsContext: PaywallAnalyticsContext? { nil }
    func didSelectProduct(_ iap: any IAPProtocol, previous: (any IAPProtocol)?) {}
}
