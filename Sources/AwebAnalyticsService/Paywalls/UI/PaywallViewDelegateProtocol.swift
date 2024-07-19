import Foundation

public protocol PaywallViewDelegateProtocol: AnyObject {
    func restore()
    func purchase(_ iap: any IAPProtocol)
    
    func termsTap(_ item: URLConvertable)
    func privacyPolicyTap(_ item: URLConvertable)
    
    func dismiss()
    func navigate(to placement: PaywallPlacementProtocol)
    
    func pricingData(_ iap: any IAPProtocol) -> PricingData?
}
