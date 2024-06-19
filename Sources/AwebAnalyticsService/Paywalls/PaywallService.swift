import UIKit
import StoreKit
import Adapty

public protocol PaywallPlacementProtocol {
    var identifier: String { get }
}

public protocol PaywallScreenProtocol: RawRepresentable where RawValue == String {
    
}

public protocol PaywallControllerProtocol: UIViewController {
    var dismissed: (() -> Void)? { get set }
}

public protocol PaywallServiceProtocol: AnyObject {
    var placements: Set<String> { get set }
    var uiFactory: ((PaywallIdentifier) -> PaywallViewProtocol)? { get set }
    func getPaywall(_ placement: PaywallPlacementProtocol) -> PaywallControllerProtocol?
}

struct PaywallAndProduct {
    let placement: String
    let adaptyPaywall: AdaptyPaywall
    let products: [AdaptyPaywallProduct]
}

public typealias PaywallIdentifier = String

public class PaywallService: PaywallServiceProtocol {
    
    public var placements = Set<String>()
    
    public var uiFactory: ((PaywallIdentifier) -> PaywallViewProtocol)?
    
    var paywallsAndProducts = [PaywallAndProduct]()
    
    let purchaseService: PurchaseService
    
    init(purchaseService: PurchaseService) {
        self.purchaseService = purchaseService
    }
        
    public func getPaywall(_ placement: PaywallPlacementProtocol) -> PaywallControllerProtocol? {
        Log.printLog(l: .debug, str: "Show paywall for placement: \(placement.identifier)")
        assert(uiFactory != nil)
        
        if let paywallData = paywallsAndProducts.first(where: { $0.placement == placement.identifier }),
           let view = uiFactory?(paywallData.adaptyPaywall.name) {
            return PaywallController(
                purchaseService: purchaseService,
                paywallView: view,
                adaptyPaywallData: paywallData
            )
        } else {
            return nil
        }
    }
    
    func fetchPaywallsAndProducts() async {
        let paywalls = await placements
            .asyncMap { identifier in
                if let paywall = try? await Adapty.getPaywall(placementId: identifier),
                   let products = try? await Adapty.getPaywallProducts(paywall: paywall) {
                    return PaywallAndProduct(placement: identifier, adaptyPaywall: paywall, products: products)
                } else {
                    return nil
                }
            }
            .compactMap { $0 }
        
        self.paywallsAndProducts = paywalls
    }
}
