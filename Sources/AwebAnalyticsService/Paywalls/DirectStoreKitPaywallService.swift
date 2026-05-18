import Foundation
import StoreKit

@MainActor
public final class DirectStoreKitPaywallService: PaywallServiceProtocol {
    
    public var placements = Set<String>()
    
    public var uiFactory: ((PaywallIdentifier) -> PaywallViewProtocol?)?
    
    public var viewIdentifiersByPlacement = [String: PaywallIdentifier]()
    
    private let purchaseService: PurchaseServiceProtocol
    private var productsByIdentifier = [String: SKProduct]()
    
    public init(purchaseService: PurchaseServiceProtocol) {
        self.purchaseService = purchaseService
    }
    
    public func setFallbackPaywalls(url: URL) {
        Log.printLog(l: .debug, str: "Fallback paywalls are not supported for direct StoreKit paywalls: \(url)")
    }
    
    public func getPaywall(_ placement: PaywallPlacementProtocol) -> PaywallControllerProtocol? {
        Log.printLog(l: .debug, str: "Show direct StoreKit paywall for placement: \(placement.identifier)")
        assert(uiFactory != nil)
        
        guard placements.contains(placement.identifier) else {
            Log.printLog(l: .error, str: "Direct StoreKit paywall placement is not configured: \(placement.identifier)")
            return nil
        }
        
        guard let viewIdentifier = viewIdentifiersByPlacement[placement.identifier] else {
            Log.printLog(l: .error, str: "Direct StoreKit paywall view identifier is missing for placement: \(placement.identifier)")
            return nil
        }
        
        guard let view = uiFactory?(viewIdentifier) else {
            Log.printLog(l: .error, str: "Direct StoreKit paywall view was not created for identifier: \(viewIdentifier)")
            return nil
        }
        
        guard !productsByIdentifier.isEmpty else {
            Log.printLog(l: .error, str: "Direct StoreKit products are not loaded")
            return nil
        }
        
        return DirectStoreKitPaywallController(
            purchaseService: purchaseService,
            paywallView: view,
            productsByIdentifier: productsByIdentifier
        )
    }
    
    public func fetchProducts() async {
        let productIdentifiers = Set(purchaseService.iaps.map(\.productID))
        guard !productIdentifiers.isEmpty else {
            productsByIdentifier = [:]
            Log.printLog(l: .error, str: "Direct StoreKit product identifiers are not configured")
            return
        }
        
        do {
            let response = try await StoreKitProductsLoader(productIdentifiers: productIdentifiers).fetch()
            if !response.invalidProductIdentifiers.isEmpty {
                Log.printLog(
                    l: .error,
                    str: "Invalid StoreKit product identifiers: \(response.invalidProductIdentifiers.joined(separator: ", "))"
                )
            }
            
            productsByIdentifier = Dictionary(
                uniqueKeysWithValues: response.products.map { ($0.productIdentifier, $0) }
            )
        } catch {
            productsByIdentifier = [:]
            Log.printLog(l: .error, str: "Failed to fetch StoreKit products: \(error.localizedDescription)")
        }
    }
}

private final class StoreKitProductsLoader: NSObject, SKProductsRequestDelegate {
    
    private let productIdentifiers: Set<String>
    private var request: SKProductsRequest?
    private var continuation: CheckedContinuation<SKProductsResponse, Error>?
    
    init(productIdentifiers: Set<String>) {
        self.productIdentifiers = productIdentifiers
    }
    
    func fetch() async throws -> SKProductsResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                
                let request = SKProductsRequest(productIdentifiers: productIdentifiers)
                request.delegate = self
                self.request = request
                request.start()
            }
        } onCancel: {
            request?.cancel()
        }
    }
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        finish(with: .success(response))
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        finish(with: .failure(error))
    }
    
    private func finish(with result: Result<SKProductsResponse, Error>) {
        request = nil
        
        switch result {
        case .success(let response):
            continuation?.resume(returning: response)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        
        continuation = nil
    }
}
