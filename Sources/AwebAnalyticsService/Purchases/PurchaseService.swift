import Foundation
import StoreKit
import ApphudSDK
import Combine

public protocol PurchaseServiceProtocol {
    func purchase(_ iap: ApphudProduct, _ completion: @escaping (PurchaseResult) -> Void)
    func restore(_ completion: @escaping (Bool) -> Void)
    
    var isSubActive: Bool { get set }
    var isSubActiveStream: AnyPublisher<Bool, Never> { get }
}

class PurchaseService: PurchaseServiceProtocol {
    
    private struct IAP: IAPProtocol {
        var productID: String
        var price: Float
    }
    
    var logEvent: ((EventProtocol) -> Void)?
    @MainActor private let isSubActiveSubject = CurrentValueSubject<Bool, Never>(Apphud.hasActiveSubscription())
    
    @MainActor func purchase(
        _ iap: ApphudSDK.ApphudProduct,
        _ completion: @escaping (PurchaseResult) -> Void
    ) {
        Apphud.purchase(iap) { result in
            
            let iapForAnalytics = IAP(
                productID: iap.productId,
                price: Float(truncating: iap.skProduct?.price ?? 0.0)
            )
            
            if let error = result.error {
                if let skError = error as? SKError, skError.code == .paymentCancelled {
                    self.logEvent?(PurchaseEvent.cancel(iap: iapForAnalytics))
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
    
    @MainActor func restore(_ completion: @escaping (Bool) -> Void) {
        Apphud.restorePurchases { subscriptions, purchases, error in
            let hasActiveSubscription = Apphud.hasActiveSubscription()
            self.isSubActive = hasActiveSubscription
            completion(hasActiveSubscription)
        }
    }
    
    @MainActor var isSubActive: Bool {
        get {
            isSubActiveSubject.value
        }
        set {
            isSubActiveSubject.send(newValue)
        }
    }
    
    @MainActor var isSubActiveStream: AnyPublisher<Bool, Never> {
        isSubActiveSubject.prepend(Apphud.hasActiveSubscription()).eraseToAnyPublisher()
    }
}
