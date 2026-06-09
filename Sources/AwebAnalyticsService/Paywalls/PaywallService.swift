import UIKit
import AdaptyUI
import StoreKit
import Adapty

public protocol PaywallPlacementProtocol: Hashable {
    var identifier: String { get }
}

public protocol PaywallScreenProtocol: RawRepresentable where RawValue == String {
    
}

public protocol PaywallControllerProtocol: UIViewController {
    var dismissed: ((_ purchasedProductID: String?) -> Void)? { get set }
    var navigated: ((PaywallPlacementProtocol) -> Void)? { get set }
    var paywallScreenID: String? { get }
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
        Adapty.setFallback(fileURL: url)
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
                    logPaywallFailed(
                        placement: placement.identifier,
                        metadata: PaywallAnalyticsError.customViewUnavailable
                    )
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
                        placement: adaptyBuilderData.placement,
                        proxy: proxy
                    )
                } catch {
                    Log.printLog(l: .error, str: "Failed to create Adapty paywall controller: \(error)")
                    logPaywallFailed(
                        placement: placement.identifier,
                        metadata: AnalyticsErrorMetadata(error: error)
                    )
                    return nil
                }
            }
        } else {
            logPaywallFailed(
                placement: placement.identifier,
                metadata: PaywallAnalyticsError.missingPaywallData
            )
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
                        let products: [AdaptyPaywallProduct]
                        do {
                            products = try await Adapty.getPaywallProducts(paywall: paywall)
                        } catch {
                            self.logPricesFailed(metadata: AnalyticsErrorMetadata(error: error))
                            throw error
                        }
                        
                        return .customPaywall(
                            CustomPaywallData(
                                placement: identifier,
                                adaptyPaywall: paywall,
                                products: products
                            )
                        )
                    }
                } catch {
                    self.analyticsService.log(
                        e: PaywallFetchErrorEvent(
                            placement: identifier,
                            errorDescription: error.localizedDescription
                        )
                    )
                    return nil
                }
            }
            .compactMap { $0 }
        
        self.paywallData = paywalls
    }
    
    private func logPricesFailed(metadata: AnalyticsErrorMetadata) {
        analyticsService.log(
            e: PricesFailedEvent(
                errorDomain: metadata.errorDomain,
                errorCode: metadata.errorCode
            )
        )
    }
    
    private func logPaywallFailed(placement: String, metadata: AnalyticsErrorMetadata) {
        analyticsService.log(
            e: PaywallFailedEvent(
                placement: placement,
                errorDomain: metadata.errorDomain,
                errorCode: metadata.errorCode
            )
        )
    }
}
