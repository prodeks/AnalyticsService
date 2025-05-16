import UIKit
import Adapty
import AdaptyUI

class AdaptyPaywallControllerWrapper: UIViewController, PaywallControllerProtocol {
    var dismissed: ((_ purchasedProductID: String?) -> Void)?
    var navigated: ((any PaywallPlacementProtocol) -> Void)?
    
    let wrappedController: AdaptyPaywallController
    let purchaseService: PurchaseService
    let proxy: AdaptyPaywallControllerDelegateProxy
    
    init(
        wrappedController: AdaptyPaywallController,
        purchaseService: PurchaseService,
        proxy: AdaptyPaywallControllerDelegateProxy
    ) {
        self.wrappedController = wrappedController
        self.purchaseService = purchaseService
        self.proxy = proxy
        super.init(nibName: nil, bundle: nil)
        
        proxy.forwarding = self
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        addChild(wrappedController)
        view.addSubview(wrappedController.view)
        wrappedController.view.frame = view.bounds
        wrappedController.didMove(toParent: self)
    }
}

class AdaptyPaywallControllerDelegateProxy: NSObject, AdaptyPaywallControllerDelegate {
    var forwarding: AdaptyPaywallControllerDelegate?
    
    public func paywallController(_ controller: AdaptyPaywallController, didPerform action: AdaptyUI.Action) {
        Log.printLog(l: .debug, str: #function)
        forwarding?.paywallController(controller, didPerform: action)
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didSelectProduct product: AdaptyPaywallProduct) {
        Log.printLog(l: .debug, str: #function)
        forwarding?.paywallController(controller, didSelectProduct: product)
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didStartPurchase product: AdaptyPaywallProduct) {
        Log.printLog(l: .debug, str: #function)
        forwarding?.paywallController(controller, didStartPurchase: product)
    }
  
    func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishPurchase product: any AdaptyPaywallProduct,
        purchaseResult: AdaptyPurchaseResult
    ) {
        Log.printLog(l: .debug, str: #function)
        forwarding?
            .paywallController(
                controller,
                didFinishPurchase: product,
                purchaseResult: purchaseResult
            )
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didFailPurchase product: AdaptyPaywallProduct, error: AdaptyError) {
        Log.printLog(l: .debug, str: #function)
        forwarding?.paywallController(controller, didFailPurchase: product, error: error)
    }
    
    public func paywallControllerDidStartRestore(_ controller: AdaptyPaywallController) {
        Log.printLog(l: .debug, str: #function)
        forwarding?.paywallControllerDidStartRestore(controller)
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didFinishRestoreWith profile: AdaptyProfile) {
        Log.printLog(l: .debug, str: #function)
        forwarding?.paywallController(controller, didFinishRestoreWith: profile)
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didFailRestoreWith error: AdaptyError) {
        Log.printLog(l: .debug, str: #function)
        forwarding?.paywallController(controller, didFailRestoreWith: error)
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didFailRenderingWith error: AdaptyError) {
        Log.printLog(l: .debug, str: #function)
        forwarding?.paywallController(controller, didFailRenderingWith: error)
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didFailLoadingProductsWith error: AdaptyError) -> Bool {
        Log.printLog(l: .debug, str: #function)
        if let forwarding {
            return forwarding.paywallController(controller, didFailLoadingProductsWith: error)
        } else {
            return false
        }
    }
}

extension AdaptyPaywallControllerWrapper: AdaptyPaywallControllerDelegate {
    public func paywallController(_ controller: AdaptyPaywallController, didPerform action: AdaptyUI.Action) {
        switch action {
        case .close:
            dismissed?(nil)
        case .openURL(let url):
            Log.printLog(l: .debug, str: "didPerform action with URL - \(url)")
            presentPolicyItem(url)
        case .custom(let id):
            Log.printLog(l: .debug, str: "didPerform action with custom ID - \(id)")
        }
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didSelectProduct product: AdaptyPaywallProduct) {
        
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didStartPurchase product: AdaptyPaywallProduct) {
        
    }
  
    func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishPurchase product: any AdaptyPaywallProduct,
        purchaseResult: AdaptyPurchaseResult
    ) {
        purchaseService.isSubActive = purchaseResult.isPurchaseSuccess
        dismissed?(product.vendorProductId)
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFailPurchase product: AdaptyPaywallProduct,
        error: AdaptyError
    ) {
        presentCannotPurchaseAlert()
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didCancelPurchase product: AdaptyPaywallProduct
    ) {
        
    }
    
    public func paywallControllerDidStartRestore(
        _ controller: AdaptyPaywallController
    ) {
        
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didFinishRestoreWith profile: AdaptyProfile) {
        let hasSub = profile.accessLevels["premium"]?.isActive ?? false
        if hasSub {
            purchaseService.isSubActive = hasSub
            dismissed?(nil)
        } else {
            presentNoPurchasesToRestoreAlert()
        }
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFailRestoreWith error: AdaptyError
    ) {
        presentNoPurchasesToRestoreAlert()
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFailRenderingWith error: AdaptyError
    ) {
        dismissed?(nil)
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFailLoadingProductsWith error: AdaptyError
    ) -> Bool {
        return false
    }
    
    func presentNoPurchasesToRestoreAlert() {
        let alert = UIAlertController(
            title: PurchasesAndAnalytics.Strings.noPurchasesToRestore,
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(.init(title: PurchasesAndAnalytics.Strings.cancel, style: .cancel))
        present(alert, animated: true)
    }
    
    func presentCannotPurchaseAlert() {
        let alert = UIAlertController(
            title: PurchasesAndAnalytics.Strings.somethingWentWrongDuringPurchase,
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(.init(title: PurchasesAndAnalytics.Strings.cancel, style: .cancel))
        present(alert, animated: true)
    }
    
    func presentPolicyItem(_ item: URLConvertable) {
        let c = WebViewController()
        let n = UINavigationController(rootViewController: c)
        c.item = item
        present(n, animated: true)
    }
}
