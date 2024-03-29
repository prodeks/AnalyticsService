import UIKit
import ApphudSDK

public protocol PaywallPlacementProtocol {
    var identifier: String { get }
}

public protocol PaywallScreenProtocol: RawRepresentable where RawValue == String {
    
}

public protocol PaywallServiceProtocol: AnyObject {
    var uiFactory: (any PaywallScreenProtocol) -> PaywallControllerProtocol? { get set }
    var apphudPlacements: [ApphudPlacement] { get set }
    
    func getPaywall<PaywallModel: PaywallScreenProtocol>(
        _ placement: PaywallPlacementProtocol,
        paywallModelType: PaywallModel.Type
    ) -> PaywallControllerProtocol?
}

public protocol PaywallControllerProtocol: UIViewController {
    var apphudProducts: [ApphudProduct] { get set }
    var dismissed: (() -> Void)? { get set }
}

class PaywallService: PaywallServiceProtocol {
    
    var uiFactory: (any PaywallScreenProtocol) -> PaywallControllerProtocol? = { _ in nil }
    var apphudPlacements: [ApphudPlacement] = []
        
    func getPaywall<PaywallModel: PaywallScreenProtocol>(
        _ placement: PaywallPlacementProtocol,
        paywallModelType: PaywallModel.Type
    ) -> PaywallControllerProtocol? {
        
        Log.printLog(l: .debug, str: "Show paywall for placement: \(placement.identifier)")
        if let apphudPaywall = apphudPlacements.first(where: { $0.identifier == placement.identifier })?.paywall,
           var localPaywall = PaywallModel(rawValue: apphudPaywall.identifier) {
            
            // unwrap json from apphud paywall to get to the actual tested value
            if let abtestedPaywall = (apphudPaywall.json?["paywallID"] as? String).flatMap(PaywallModel.init) {
                localPaywall = abtestedPaywall
            }
            
            let controller = uiFactory(localPaywall)
            let products = apphudPaywall.products
            controller?.apphudProducts = products
            return controller
        } else {
            Log.printLog(l: .error, str: "Could not fetch paywall for placement: \(placement.identifier)")
            return nil
        }
    }
}
