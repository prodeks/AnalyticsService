import Foundation

public protocol PaywallViewDelegateProtocol: AnyObject {
    func restore()
    func purchase(_ iap: IAPProtocol)
    
    func termsTap(_ item: URLConvertable)
    func privacyPolicyTap(_ item: URLConvertable)
    
    func dismiss()
    
    func pricingData(_ iap: IAPProtocol) -> PricingData?
}