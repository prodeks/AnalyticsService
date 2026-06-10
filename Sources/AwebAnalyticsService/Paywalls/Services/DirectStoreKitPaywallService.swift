import Foundation
import StoreKit

@MainActor
public final class DirectStoreKitPaywallService: PaywallServiceProtocol {
    
    public var placements = Set<String>()
    
    public var uiFactory: ((PaywallIdentifier) -> PaywallViewProtocol?)?
    
    public var viewIdentifiersByPlacement = [String: PaywallIdentifier]()
    
    private let purchaseService: PurchaseServiceProtocol
    private let logEvent: ((EventProtocol) -> Void)?
    private var productsByIdentifier = [String: StoreKit.Product]()
    
    public init(
        purchaseService: PurchaseServiceProtocol,
        logEvent: ((EventProtocol) -> Void)? = nil
    ) {
        self.purchaseService = purchaseService
        self.logEvent = logEvent
    }
    
    public func setFallbackPaywalls(url: URL) {
        Log.printLog(l: .debug, str: "Fallback paywalls are not supported for direct StoreKit paywalls: \(url)")
    }
    
    public func getPaywall(_ placement: PaywallPlacementProtocol) -> PaywallControllerProtocol? {
        Log.printLog(l: .debug, str: "Show direct StoreKit paywall for placement: \(placement.identifier)")
        assert(uiFactory != nil)
        
        guard placements.contains(placement.identifier) else {
            Log.printLog(l: .error, str: "Direct StoreKit paywall placement is not configured: \(placement.identifier)")
            logPaywallFailed(
                placement: placement.identifier,
                metadata: PaywallAnalyticsError.unconfiguredPlacement
            )
            return nil
        }
        
        guard let viewIdentifier = viewIdentifiersByPlacement[placement.identifier] else {
            Log.printLog(l: .error, str: "Direct StoreKit paywall view identifier is missing for placement: \(placement.identifier)")
            logPaywallFailed(
                placement: placement.identifier,
                metadata: PaywallAnalyticsError.missingViewIdentifier
            )
            return nil
        }
        
        guard let view = uiFactory?(viewIdentifier) else {
            Log.printLog(l: .error, str: "Direct StoreKit paywall view was not created for identifier: \(viewIdentifier)")
            logPaywallFailed(
                placement: placement.identifier,
                metadata: PaywallAnalyticsError.customViewUnavailable
            )
            return nil
        }
        
        guard !productsByIdentifier.isEmpty else {
            Log.printLog(l: .error, str: "Direct StoreKit products are not loaded")
            logPaywallFailed(
                placement: placement.identifier,
                metadata: PaywallAnalyticsError.productsNotLoaded
            )
            return nil
        }
        
        return DirectStoreKitPaywallController(
            purchaseService: purchaseService,
            paywallView: view,
            productsByIdentifier: productsByIdentifier,
            presentationContext: PaywallPresentationContext(
                paywallID: view.paywallID.rawValue,
                placement: placement.identifier,
                source: .storeKit
            ),
            logEvent: { [logEvent] event in
                logEvent?(event)
            }
        )
    }
    
    public func fetchProducts() async {
        let productIdentifiers = Set(purchaseService.iaps.map(\.productID))
        guard !productIdentifiers.isEmpty else {
            let description = "Direct StoreKit product identifiers are not configured"
            productsByIdentifier = [:]
            Log.printLog(l: .error, str: description)
            logPricesFailed(metadata: PaywallAnalyticsError.missingProductIdentifiers)
            logPaywallFetchError(
                metadata: PaywallAnalyticsError.missingProductIdentifiers,
                description: description
            )
            return
        }
        
        do {
            let products = try await Product.products(for: productIdentifiers)
            let loadedIdentifiers = Set(products.map(\.id))
            let invalidProductIdentifiers = productIdentifiers.subtracting(loadedIdentifiers).sorted()
            if !invalidProductIdentifiers.isEmpty {
                logPricesFailed(
                    metadata: PaywallAnalyticsError.invalidProductIdentifiers,
                    failedIdentifiers: invalidProductIdentifiers
                )
                Log.printLog(
                    l: .error,
                    str: "Invalid StoreKit product identifiers: \(invalidProductIdentifiers.joined(separator: ", "))"
                )
            }
            
            if products.isEmpty {
                let description = "Direct StoreKit products are not loaded"
                logPricesFailed(metadata: PaywallAnalyticsError.productsNotLoaded)
                logPaywallFetchError(
                    metadata: PaywallAnalyticsError.productsNotLoaded,
                    description: description
                )
            }
            
            productsByIdentifier = Dictionary(
                uniqueKeysWithValues: products.map { ($0.id, $0) }
            )
        } catch {
            let description = "Failed to fetch StoreKit products: \(error.localizedDescription)"
            let metadata = AnalyticsErrorMetadata(error: error)
            productsByIdentifier = [:]
            logPricesFailed(metadata: metadata)
            logPaywallFetchError(metadata: metadata, description: description)
            Log.printLog(l: .error, str: description)
        }
    }
    
    private func logPricesFailed(metadata: AnalyticsErrorMetadata, failedIdentifiers: [String] = []) {
        logEvent?(
            PricesFailedEvent(
                source: .storeKit,
                metadata: metadata,
                failedIdentifiers: failedIdentifiers
            )
        )
    }
    
    private func logPaywallFailed(placement: String, metadata: AnalyticsErrorMetadata) {
        logEvent?(
            PaywallFailedEvent(
                source: .storeKit,
                placement: placement,
                metadata: metadata
            )
        )
    }

    private func logPaywallFetchError(metadata: AnalyticsErrorMetadata, description: String) {
        let affectedPlacements = placements.isEmpty ? ["unknown"] : placements
        for placement in affectedPlacements {
            logEvent?(
                PaywallFetchErrorEvent(
                    source: .storeKit,
                    placement: placement,
                    errorDescription: description,
                    errorDomain: metadata.errorDomain,
                    errorCode: metadata.errorCode
                )
            )
        }
    }
}
