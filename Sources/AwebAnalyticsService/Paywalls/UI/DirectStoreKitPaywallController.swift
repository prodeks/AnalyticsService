import StoreKit
import UIKit

final class DirectStoreKitPaywallController: UIViewController, PaywallViewDelegateProtocol, UIViewControllerTransitioningDelegate, PaywallControllerProtocol {
    
    var dismissed: ((_ purchasedProductID: String?) -> Void)?
    var navigated: ((PaywallPlacementProtocol) -> Void)?
    
    private let overlayView = LoaderOverlayView()
    private let purchaseService: PurchaseServiceProtocol
    private let paywallView: any PaywallViewProtocol
    private let productsByIdentifier: [String: StoreKit.Product]
    
    public var paywallScreenID: String? { paywallView.paywallID.rawValue }

    private var presentationContext: PaywallPresentationContext?
    private var logEvent: ((EventProtocol) -> Void)?
    private var didLogOpen = false

    init(
        purchaseService: PurchaseServiceProtocol,
        paywallView: any PaywallViewProtocol,
        productsByIdentifier: [String: StoreKit.Product],
        presentationContext: PaywallPresentationContext,
        logEvent: @escaping (EventProtocol) -> Void
    ) {
        self.purchaseService = purchaseService
        self.paywallView = paywallView
        self.productsByIdentifier = productsByIdentifier
        self.presentationContext = presentationContext
        self.logEvent = logEvent

        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = paywallView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        paywallView.delegate = self
        view.addSubview(overlayView)
        overlayView.isHidden = true
        
        if let navigationController {
            navigationController.setNavigationBarHidden(true, animated: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !didLogOpen, let presentationContext else { return }
        didLogOpen = true
        logEvent?(PaywallOpenEvent(context: presentationContext))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        overlayView.frame = view.bounds
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let navigationController {
            navigationController.setNavigationBarHidden(false, animated: false)
        }
    }
    
    func pricingData(_ iap: any IAPProtocol) -> PricingData? {
        guard let product = productsByIdentifier[iap.productID] else {
            return nil
        }
        let introductoryOffer = product.subscription?.introductoryOffer
        
        return PricingData(
            value: Double(truncating: product.price as NSDecimalNumber),
            priceLocale: product.priceFormatStyle.locale,
            currencySymbol: product.priceFormatStyle.locale.currencySymbol ?? "",
            introOfferValue: introductoryOffer.map { Double(truncating: $0.price as NSDecimalNumber) },
            introOfferLocalizedPrice: introductoryOffer?.displayPrice,
            iap: iap
        )
    }
    
    func restore() {
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
    
    func purchase(_ iap: any IAPProtocol) {
        overlayView.isHidden = false
        if let product = productsByIdentifier[iap.productID], let presentationContext {
            purchaseService.purchaseProduct(
                product,
                paywallID: presentationContext.paywallID,
                placement: presentationContext.placement,
                presentationID: presentationContext.presentationID
            ) { [weak self] result in
                guard let self else { return }
                self.overlayView.isHidden = true
                
                switch result {
                case .cancel:
                    break
                case .fail:
                    self.presentCannotPurchaseAlert()
                case .success:
                    self.dismiss(iap.productID)
                }
            }
        } else {
            presentCannotPurchaseAlert()
            overlayView.isHidden = true
        }
    }
    
    func termsTap(_ item: URLConvertable) {
        presentPolicyItem(item)
    }
    
    func privacyPolicyTap(_ item: URLConvertable) {
        presentPolicyItem(item)
    }
    
    func navigate(to placement: PaywallPlacementProtocol) {
        navigated?(placement)
    }
    
    func dismiss() {
        dismiss(nil)
    }
    
    private func dismiss(_ purchasedProductID: String?) {
        if let presentationContext {
            logEvent?(PaywallClosedEvent(
                context: presentationContext,
                purchased: purchasedProductID != nil
            ))
        }

        if let presented = presentedViewController {
            presented.dismiss(animated: true) {
                self.dismissed?(purchasedProductID)
            }
        } else {
            dismissed?(purchasedProductID)
        }
    }
    
    private func presentNoPurchasesToRestoreAlert() {
        let alert = UIAlertController(
            title: PurchasesAndAnalytics.Strings.noPurchasesToRestore,
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(.init(title: PurchasesAndAnalytics.Strings.cancel, style: .cancel))
        if let presented = presentedViewController {
                presented.present(alert, animated: true)
        } else {
            present(alert, animated: true)
        }
    }
    
    private func presentCannotPurchaseAlert() {
        let alert = UIAlertController(
            title: PurchasesAndAnalytics.Strings.somethingWentWrongDuringPurchase,
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(.init(title: PurchasesAndAnalytics.Strings.cancel, style: .cancel))
        if let presented = presentedViewController {
                presented.present(alert, animated: true)
        } else {
            present(alert, animated: true)
        }
    }
    
    private func presentPolicyItem(_ item: URLConvertable) {
        let controller = WebViewController()
        let navigationController = UINavigationController(rootViewController: controller)
        controller.item = item
        if let presented = presentedViewController {
            presented.present(navigationController, animated: true)
        } else {
            present(navigationController, animated: true)
        }
    }
}
