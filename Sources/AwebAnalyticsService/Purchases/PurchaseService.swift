import Foundation
import StoreKit
import SwiftyStoreKit
import Combine

public protocol PurchaseServiceProtocol: AnyObject {
    var iaps: [any IAPProtocol] { get set }
    var isSubActive: Bool { get }
    var isSubActiveStream: AnyPublisher<Bool, Never> { get }
    func purchase( _ iap: any IAPProtocol, paywallID: String, _ completion: @escaping (PurchaseResult) -> Void)
    func restore(_ completion: @escaping (Bool) -> Void)
    func verifySubscriptions(_ completion: @escaping (Bool) -> Void)
}

public class PurchaseService: PurchaseServiceProtocol {
    
    /// Assign to this variable all your available  in app purchase models
    public var iaps: [any IAPProtocol] = []
    
    var logEvent: ((EventProtocol) -> Void)?
    
    public var isSubActive: Bool {
        get {
            UserDefaults.standard.isSubActive
        }
        set {
            UserDefaults.standard.isSubActive = newValue
            relay.send(newValue)
        }
    }
    
    public var isSubActiveStream: AnyPublisher<Bool, Never> {
        relay.eraseToAnyPublisher()
    }
    
    private let relay = CurrentValueSubject<Bool, Never>(UserDefaults.standard.isSubActive)
    
    @MainActor public func purchase(
        _ iap: any IAPProtocol,
        paywallID: String,
        _ completion: @escaping (PurchaseResult) -> Void
    ) {
        self.logEvent?(PaywallCheckoutStartedEvent(paywallID: paywallID))
        SwiftyStoreKit.purchaseProduct(iap.productID) { purchaseResult in
            
            switch purchaseResult {
            case .deferred, .success:
                self.isSubActive = true
                self.logEvent?(PurchaseEvent.success(iap: (iap.productID, iap.price)))
                completion(.success)
            case .error(let error):
                if error.code == .paymentCancelled {
                    self.logEvent?(PurchaseEvent.cancel(iap: (iap.productID, iap.price)))
                    self.logEvent?(PaywallCheckoutCancelledEvent(paywallID: paywallID))
                    completion(.cancel)
                } else {
                    self.logEvent?(PurchaseEvent.fail(iap: (iap.productID, iap.price)))
                    completion(.fail)
                }
            }
        }
    }
    
    @MainActor public func restore(_ completion: @escaping (Bool) -> Void) {
        SwiftyStoreKit.restorePurchases { restoreResults in
            guard !restoreResults.restoredPurchases.isEmpty else {
                completion(false)
                return
            }
            self.verifySubscriptions(completion)
        }
    }
    
    func getProducts() async -> [SKProduct] {
        assert(!iaps.isEmpty)
        return await withCheckedContinuation { c in
            SwiftyStoreKit.retrieveProductsInfo(Set(iaps.map { $0.productID })) { retrieveResults in
                let products = retrieveResults.retrievedProducts.map { $0 }
                c.resume(with: .success(products))
            }
        }
    }
    
    func verifySubscriptionIfNeeded() async {
        await withCheckedContinuation { c in
            if isSubActive {
                verifySubscriptions { hasSub in
                    self.isSubActive = hasSub
                    c.resume()
                }
            } else {
                c.resume()
            }
        }
    }
    
    public func verifySubscriptions(_ completion: @escaping (Bool) -> Void) {
        let appleValidator = AppleReceiptValidator(
            service: value(debug: { .sandbox }, release: { .production }),
            sharedSecret: PurchasesAndAnalytics.Keys.sharedSecret
        )
        
        SwiftyStoreKit.verifyReceipt(using: appleValidator) { result in
            switch result {
            case .success(let receipt):
                let purchasedSub = self.iaps.filter { iap in
                    
                    let purchaseResult = SwiftyStoreKit.verifySubscription(
                        ofType: iap.type.swiftyStoreKitValue(),
                        productId: iap.productID,
                        inReceipt: receipt
                    )
                    
                    if case .purchased(let expiryDate, _) = purchaseResult {
                        return expiryDate > Date()
                    } else {
                        return false
                    }
                }
                
                let hasActiveSub = !purchasedSub.isEmpty
                
                completion(hasActiveSub)
                
            case .error:
                completion(false)
            }
        }
    }
    
}

extension UserDefaults {
    @objc var isSubActive: Bool {
        get {
            return bool(forKey: "isSubActive")
//            true
        }
        set {
            set(newValue, forKey: "isSubActive")
        }
    }
}

func value<T>(debug: () -> T, release: () -> T) -> T {
#if DEBUG
    return debug()
#else
    return release()
#endif
}
