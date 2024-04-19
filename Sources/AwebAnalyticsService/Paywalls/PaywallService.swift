import UIKit
import StoreKit

public protocol PaywallPlacementProtocol {
    var identifier: String { get }
}

public protocol PaywallScreenProtocol: RawRepresentable where RawValue == String {
    
}

public protocol PaywallControllerProtocol: UIViewController {
    var products: [SKProduct] { get set }
    var dismissed: (() -> Void)? { get set }
}

public protocol PaywallServiceProtocol: AnyObject {
    var uiFactory: ((PaywallPlacementProtocol) -> PaywallControllerProtocol)? { get set }
    func getPaywall(_ placement: PaywallPlacementProtocol) -> PaywallControllerProtocol?
}

public class PaywallService: PaywallServiceProtocol {
    var products: [SKProduct] = []
    
    public var uiFactory: ((PaywallPlacementProtocol) -> PaywallControllerProtocol)?
        
    public func getPaywall(_ placement: PaywallPlacementProtocol) -> PaywallControllerProtocol? {
        Log.printLog(l: .debug, str: "Show paywall for placement: \(placement.identifier)")
        let controller = uiFactory?(placement)
        controller?.products = products
        return controller
    }
}
