import Foundation
import StoreKit
import ApphudSDK
import Combine

public protocol PurchaseServiceProtocol {
    func purchase(_ iap: ApphudProduct, paywallID: String, _ completion: @escaping (PurchaseResult) -> Void)
    func restore(_ completion: @escaping (Bool) -> Void)
    
    var isSubActive: Bool { get set }
    var isSubActiveStream: AnyPublisher<Bool, Never> { get }
}

public class PurchaseService: PurchaseServiceProtocol {
    
    private struct IAP: IAPProtocol {
        var productID: String
        var price: Float
    }
    
    var logEvent: ((EventProtocol) -> Void)?
    @MainActor private let isSubActiveSubject = CurrentValueSubject<Bool, Never>(Apphud.hasActiveSubscription())
    
    @MainActor public func purchase(
        _ iap: ApphudSDK.ApphudProduct,
        paywallID: String,
        _ completion: @escaping (PurchaseResult) -> Void
    ) {
        self.logEvent?(PaywallCheckoutStartedEvent(paywallID: paywallID))
        Apphud.purchase(iap) { result in
            
            let iapForAnalytics = IAP(
                productID: iap.productId,
                price: Float(truncating: iap.skProduct?.price ?? 0.0)
            )
            
            if let error = result.error {
                if let skError = error as? SKError, skError.code == .paymentCancelled {
                    self.logEvent?(PurchaseEvent.cancel(iap: iapForAnalytics))
                    self.logEvent?(PaywallCheckoutCancelledEvent(paywallID: paywallID))
                    completion(.cancel)
                } else {
                    self.logEvent?(PurchaseEvent.fail(iap: iapForAnalytics))
                    completion(.fail)
                }
            } else {
                self.isSubActive = true
                self.logEvent?(PurchaseEvent.success(iap: iapForAnalytics))
                completion(.success)
            }
        }
    }
    
    @MainActor public func restore(_ completion: @escaping (Bool) -> Void) {
        Apphud.restorePurchases { subscriptions, purchases, error in
            let hasActiveSubscription = Apphud.hasActiveSubscription()
            self.isSubActive = hasActiveSubscription
            completion(hasActiveSubscription)
        }
    }
    
    @MainActor public var isSubActive: Bool {
        get {
            isSubActiveSubject.value
        }
        set {
            isSubActiveSubject.send(newValue)
        }
    }
    
    @MainActor public var isSubActiveStream: AnyPublisher<Bool, Never> {
        isSubActiveSubject.prepend(Apphud.hasActiveSubscription()).eraseToAnyPublisher()
    }
}
