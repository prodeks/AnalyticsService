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
    public var logOpen: (() -> Void)?
    public var logClose: (() -> Void)?
    
    let overlayView = LoaderOverlayView()
    let purchaseService: any PurchaseServiceProtocol
    
    init(
        purchaseService: PurchaseService
    ) {
        self.purchaseService = purchaseService
        
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
        
        logOpen?()
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
    }
    
    public func purchase(_ iap: IAPProtocol) {
        self.overlayView.isHidden = false
        if let apphudProduct = apphudProducts.first(where: { $0.productId == iap.productID }) {
            purchaseService.purchase(
                apphudProduct,
                paywallID: paywallView.appHudPaywallID.rawValue
            ) { [weak self] result in
                guard let self = self else { return }
                self.overlayView.isHidden = true
                
                switch result {
                case .cancel:
                    break
                case .fail:
                    self.presentCannotPurchaseAlert()
                case .success:
                    self.dismiss()
                }
            }
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
        logClose?()
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
