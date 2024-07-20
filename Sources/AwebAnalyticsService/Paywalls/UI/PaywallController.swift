import Foundation
import StoreKit
import Lottie
import Adapty

public class PaywallController: UIViewController, PaywallViewDelegateProtocol, UIViewControllerTransitioningDelegate, PaywallControllerProtocol {
    
    public var dismissed: (() -> Void)?
    public var navigated: ((PaywallPlacementProtocol) -> Void)?
    public var logOpen: (() -> Void)?
    public var logClose: (() -> Void)?
    
    let overlayView = LoaderOverlayView()
    let purchaseService: PurchaseService
    let adaptyPaywallData: PaywallAndProduct
    let paywallView: any PaywallViewProtocol
    
    init(
        purchaseService: PurchaseService, 
        paywallView: any PaywallViewProtocol,
        adaptyPaywallData: PaywallAndProduct
    ) {
        self.paywallView = paywallView
        self.purchaseService = purchaseService
        self.adaptyPaywallData = adaptyPaywallData
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        view = paywallView
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        paywallView.delegate = self
        view.addSubview(overlayView)
        overlayView.isHidden = true
        
        if let navigationController {
            navigationController.setNavigationBarHidden(true, animated: false)
        }
        
        Adapty.logShowPaywall(adaptyPaywallData.adaptyPaywall)
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        overlayView.frame = view.bounds
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let navigationController {
            navigationController.setNavigationBarHidden(false, animated: false)
        }
    }
    
    public func pricingData(_ iap: any IAPProtocol) -> PricingData? {
        return adaptyPaywallData.products
            .first(where: { $0.skProduct.productIdentifier == iap.productID })
            .flatMap { product in
                PricingData(
                    value: Double(truncating: product.skProduct.price),
                    localizedPrice: product.localizedPrice ?? "",
                    priceLocale: product.skProduct.priceLocale
                )
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
    
    public func purchase(_ iap: any IAPProtocol) {
        self.overlayView.isHidden = false
        if let product = adaptyPaywallData.products.first(where: { $0.skProduct.productIdentifier == iap.productID }) {
            purchaseService.purchaseAdaptyProduct(
                product,
                paywallID: paywallView.paywallID.rawValue
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
    
    public func navigate(to placement: PaywallPlacementProtocol) {
        navigated?(placement)
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
