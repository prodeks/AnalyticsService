import UIKit
import AdaptyUI
import StoreKit
import Adapty

public protocol PaywallPlacementProtocol {
    var identifier: String { get }
}

public protocol PaywallScreenProtocol: RawRepresentable where RawValue == String {
    
}

public protocol PaywallControllerProtocol: UIViewController {
    var dismissed: ((_ purchasedProductID: String?) -> Void)? { get set }
    var navigated: ((PaywallPlacementProtocol) -> Void)? { get set }
}

@MainActor public protocol PaywallServiceProtocol: AnyObject {
    var placements: Set<String> { get set }
    var uiFactory: ((PaywallIdentifier) -> PaywallViewProtocol?)? { get set }
    func getPaywall(_ placement: PaywallPlacementProtocol) -> PaywallControllerProtocol?
    func setFallbackPaywalls(url: URL)
}

enum PaywallData {
    case customPaywall(CustomPaywallData)
    case adaptyBuilder(AdaptyBuilderData)
    
    var placementID: String {
        switch self {
        case .customPaywall(let customPaywallData):
            return customPaywallData.placement
        case .adaptyBuilder(let adaptyBuilderData):
            return adaptyBuilderData.placement
        }
    }
}

struct AdaptyBuilderData {
    let placement: String
    let adaptyPaywall: AdaptyPaywall
    let configuration: AdaptyUI.PaywallConfiguration
}

struct CustomPaywallData {
    let placement: String
    let adaptyPaywall: AdaptyPaywall
    let products: [AdaptyPaywallProduct]
}

public typealias PaywallIdentifier = String

class PaywallService: PaywallServiceProtocol {
    
    public var placements = Set<String>()
    
    public var uiFactory: ((PaywallIdentifier) -> PaywallViewProtocol?)?
    
    var paywallData = [PaywallData]()
    
    let purchaseService: PurchaseService
    let analyticsService: AnalyticsService
    
    init(purchaseService: PurchaseService, analyticsService: AnalyticsService) {
        self.purchaseService = purchaseService
        self.analyticsService = analyticsService
    }
    
    public func setFallbackPaywalls(url: URL) {
        Adapty.setFallbackPaywalls(fileURL: url)
    }
    
    public func getPaywall(_ placement: PaywallPlacementProtocol) -> PaywallControllerProtocol? {
        Log.printLog(l: .debug, str: "Show paywall for placement: \(placement.identifier)")
        assert(uiFactory != nil)
        
        if let paywallData = paywallData.first(where: { $0.placementID == placement.identifier }) {
            switch paywallData {
            case .customPaywall(let customPaywallData):
                if let view = uiFactory?(customPaywallData.adaptyPaywall.name) {
                    return PaywallController(
                        purchaseService: purchaseService,
                        paywallView: view,
                        adaptyPaywallData: customPaywallData
                    )
                } else {
                    return nil
                }
            case .adaptyBuilder(let adaptyBuilderData):
                do {
                    let proxy = AdaptyPaywallControllerDelegateProxy()
                    let adaptyController = try AdaptyUI.paywallController(
                        with: adaptyBuilderData.configuration,
                        delegate: proxy
                    )
                    return AdaptyPaywallControllerWrapper(
                        wrappedController: adaptyController,
                        purchaseService: purchaseService,
                        analyticsService: analyticsService,
                        proxy: proxy
                    )
                } catch {
                    Log.printLog(l: .error, str: "Failed to create Adapty paywall controller: \(error)")
                    return nil
                }
            }
        } else {
            return nil
        }
    }
    
    func fetchPaywallsAndProducts() async {
        let paywalls = await placements
            .asyncMap { identifier -> PaywallData? in
                do {
                    let paywall = try await Adapty.getPaywall(placementId: identifier)
                    if paywall.hasViewConfiguration {
                        let config = try await AdaptyUI.getPaywallConfiguration(forPaywall: paywall)
                        return .adaptyBuilder(
                            AdaptyBuilderData(
                                placement: identifier,
                                adaptyPaywall: paywall,
                                configuration: config
                            )
                        )
                    } else {
                        let products = try await Adapty.getPaywallProducts(paywall: paywall)
                        return .customPaywall(
                            CustomPaywallData(
                                placement: identifier,
                                adaptyPaywall: paywall,
                                products: products
                            )
                        )
                    }
                } catch {
                    Log.printLog(l: .error, str: "Failed to fetch paywall for placement: \(identifier)")
                    return nil
                }
            }
            .compactMap { $0 }
        
        self.paywallData = paywalls
    }
}
