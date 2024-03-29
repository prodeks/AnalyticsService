import Foundation
import StoreKit
import Lottie
import ApphudSDK

public class PaywallController<V: PaywallViewProtocol>: UIViewController, 
                                                            PaywallViewDelegateProtocol,
                                                            UIViewControllerTransitioningDelegate,
                                                            PaywallControllerProtocol {
    
    public var apphudProducts: [ApphudSDK.ApphudProduct] = []
    public var dismissed: (() -> Void)?
    
    let overlayView = LoaderOverlayView()
    
    let purchaseService: any PurchaseServiceProtocol
    
    init(
        purchaseService: PurchaseService,
        dismissed: ( () -> Void)? = nil
    ) {
        self.purchaseService = purchaseService
        self.dismissed = dismissed
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var paywallView: V {
        return view as! V
    }
    
    public override func loadView() {
        view = V()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        paywallView.delegate = self
        view.addSubview(overlayView)
        overlayView.isHidden = true
        overlayView.frame = view.bounds
        
        if let navigationController {
            navigationController.setNavigationBarHidden(true, animated: false)
        }
    }
    
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let navigationController {
            navigationController.setNavigationBarHidden(false, animated: false)
        }
    }
    
    public func pricingData(_ iap: IAPProtocol) -> PricingData? {
        return apphudProducts
            .first(where: { $0.productId == iap.productID })
            .flatMap { apphudProduct in
                return apphudProduct.skProduct.map { skProduct in
                    PricingData(localizedPrice: skProduct.localizedPrice ?? "")
                }
            }
    }
    
    public func restore() {
        overlayView.isHidden = false
        purchaseService.restore { [weak self] restored in
            self?.overlayView.isHidden = true
            if restored {
                
                self?.dismiss()
            } else {
                self?.presentNoPurchasesToRestoreAlert()
            }
        }
//        Current.purchaseService().restore { [weak self] restored in
//            self?.overlayView.isHidden = true
//            if restored {
//                self?.dismiss()
//                Current.subscriptionService().isSubActive = true
//            } else {
//                self?.presentNoPurchasesToRestoreAlert()
//            }
//        }
    }
    
    public func purchase(_ iap: IAPProtocol) {
//        Current.analyticsService().log(e: PaywallCheckoutStartedEvent(paywallID: paywallView.appHudPaywallID.rawValue))
        self.overlayView.isHidden = false
        if let apphudProduct = apphudProducts.first(where: { $0.productId == iap.productID }) {
//            Current.purchaseService().purchase(apphudProduct) { [weak self] result in
//                guard let self = self else { return }
//                self.overlayView.isHidden = true
//                
//                switch result {
//                case .cancel:
//                    Current.analyticsService().log(
//                        e: PaywallCheckoutCancelledEvent(
//                            paywallID: self.paywallView.appHudPaywallID.rawValue
//                        )
//                    )
//                case .fail:
//                    self.presentCannotPurchaseAlert()
//                case .success:
//                    self.dismiss()
//                    Current.subscriptionService().isSubActive = true
//                }
//            }
        } else {
            self.presentCannotPurchaseAlert()
            self.overlayView.isHidden = true
        }
    }
    
    public func termsTap(_ item: URLConvertable) {
        presentPolicyItem(item)
    }
    
    public func privacyPolicyTap(_ item: URLConvertable) {
        presentPolicyItem(item)
    }
    
    public func dismiss() {
//        Current.analyticsService().log(e: PaywallClosedEvent(paywallID: paywallView.appHudPaywallID.rawValue))
        dismissed?()
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
