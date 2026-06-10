import UIKit
import Adapty
import AdaptyUI

class AdaptyPaywallControllerWrapper: UIViewController, PaywallControllerProtocol {
    var dismissed: ((_ purchasedProductID: String?) -> Void)?
    var navigated: ((any PaywallPlacementProtocol) -> Void)?
    var paywallScreenID: String? { nil }
    
    let wrappedController: AdaptyPaywallController
    let purchaseService: PurchaseService
    let analyticsService: AnalyticsService
    let placement: String
    let proxy: AdaptyPaywallControllerDelegateProxy
    private let presentationContext: PaywallPresentationContext
    private var didLogOpen = false

    init(
        wrappedController: AdaptyPaywallController,
        purchaseService: PurchaseService,
        analyticsService: AnalyticsService,
        placement: String,
        proxy: AdaptyPaywallControllerDelegateProxy,
        presentationContext: PaywallPresentationContext
    ) {
        self.analyticsService = analyticsService
        self.wrappedController = wrappedController
        self.purchaseService = purchaseService
        self.placement = placement
        self.proxy = proxy
        self.presentationContext = presentationContext
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !didLogOpen else { return }
        didLogOpen = true
        analyticsService.log(e: PaywallOpenEvent(context: presentationContext))
    }

    private func dismissPaywall(purchasedProductID: String?) {
        analyticsService.log(e: PaywallClosedEvent(
            context: presentationContext,
            purchased: purchasedProductID != nil
        ))
        dismissed?(purchasedProductID)
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
    
    func paywallController(_ controller: AdaptyPaywallController, didFailRenderingWith error: AdaptyUIError) {
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
            dismissPaywall(purchasedProductID: nil)
        case .openURL(let url):
            Log.printLog(l: .debug, str: "didPerform action with URL - \(url)")
            presentPolicyItem(url)
        case .custom(let id):
            Log.printLog(l: .debug, str: "didPerform action with custom ID - \(id)")
        }
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didSelectProduct product: any AdaptyPaywallProductWithoutDeterminingOffer
    ) {
        
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didStartPurchase product: AdaptyPaywallProduct
    ) {
        Log.printLog(l: .debug, str: #function)
        PaywallEventLogger.checkoutStarted(
            checkoutContext(product: product),
            log: analyticsService.log(e:)
        )
    }
  
    func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishPurchase product: any AdaptyPaywallProduct,
        purchaseResult: AdaptyPurchaseResult
    ) {
        purchaseService.subscriptionStatus = purchaseResult.isPurchaseSuccess ? .active : .inactive
        let context = checkoutContext(product: product)
        if purchaseResult.isPurchaseSuccess {
            PaywallEventLogger.purchaseSucceeded(context, log: analyticsService.log(e:))
        } else if purchaseResult.isPurchaseCancelled {
            PaywallEventLogger.purchaseCancelled(context, log: analyticsService.log(e:))
        }
        dismissPaywall(purchasedProductID: product.vendorProductId)
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFailPurchase product: AdaptyPaywallProduct,
        error: AdaptyError
    ) {
        let metadata = PaywallFailureMetadata(error: error)
        PaywallEventLogger.purchaseFailed(
            checkoutContext(product: product),
            adaptyError: error,
            reason: metadata.reason,
            log: analyticsService.log(e:)
        )
        presentCannotPurchaseAlert()
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didCancelPurchase product: AdaptyPaywallProduct
    ) {
        PaywallEventLogger.purchaseCancelled(
            checkoutContext(product: product),
            log: analyticsService.log(e:)
        )
    }
    
    public func paywallControllerDidStartRestore(
        _ controller: AdaptyPaywallController
    ) {
        
    }
    
    public func paywallController(_ controller: AdaptyPaywallController, didFinishRestoreWith profile: AdaptyProfile) {
        if let subscriptionStatus = profile.accessLevels["premium"]?.subscriptionStatus {
            purchaseService.subscriptionStatus = subscriptionStatus
            if subscriptionStatus.isSubActive {
                PaywallEventLogger.restoreSucceeded(source: .adapty, log: analyticsService.log(e:))
                dismissPaywall(purchasedProductID: nil)
            } else {
                presentNoPurchasesToRestoreAlert()
            }
        }
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFailRestoreWith error: AdaptyError
    ) {
        logRestoreFailed(metadata: PaywallFailureMetadata(error: error))
        presentNoPurchasesToRestoreAlert()
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFailRenderingWith error: AdaptyUIError
    ) {
        logPaywallFailed(metadata: AnalyticsErrorMetadata(error: error))
        dismissPaywall(purchasedProductID: nil)
    }
    
    public func paywallController(
        _ controller: AdaptyPaywallController,
        didFailLoadingProductsWith error: AdaptyError
    ) -> Bool {
        logPricesFailed(metadata: AnalyticsErrorMetadata(error: error))
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
    
    private func checkoutContext(product: any AdaptyPaywallProduct) -> PaywallCheckoutContext {
        PaywallCheckoutContext(
            paywallID: presentationContext.paywallID,
            placement: placement,
            product: AdaptyProductContext(product: product),
            variationId: presentationContext.variationId,
            presentationID: presentationContext.presentationID,
            source: .adapty
        )
    }
    
    private func logRestoreFailed(metadata: PaywallFailureMetadata) {
        PaywallEventLogger.restoreFailed(
            reason: metadata.reason,
            source: .adapty,
            errorDomain: metadata.errorDomain,
            errorCode: metadata.errorCode,
            log: analyticsService.log(e:)
        )
    }
    
    private func logPricesFailed(metadata: AnalyticsErrorMetadata) {
        analyticsService.log(
            e: PricesFailedEvent(
                source: .adapty,
                metadata: metadata
            )
        )
    }
    
    private func logPaywallFailed(metadata: AnalyticsErrorMetadata) {
        analyticsService.log(
            e: PaywallFailedEvent(
                source: .adapty,
                placement: placement,
                metadata: metadata
            )
        )
    }
}
