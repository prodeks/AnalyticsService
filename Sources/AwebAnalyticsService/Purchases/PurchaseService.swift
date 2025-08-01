import Foundation
import StoreKit
import Combine
import Adapty

public protocol PurchaseServiceProtocol: AnyObject {
    var iaps: [any IAPProtocol] { get set }
    var isSubActive: Bool { get set }
    var isSubActiveStream: AnyPublisher<Bool, Never> { get }
    func purchaseAdaptyProduct(_ product: AdaptyPaywallProduct, paywallID: String, _ completion: @escaping (PurchaseResult) -> Void)
    func restore(_ completion: @escaping (Bool) -> Void)
}

class PurchaseService: PurchaseServiceProtocol {
    
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
    
    public func purchaseAdaptyProduct(_ product: AdaptyPaywallProduct, paywallID: String, _ completion: @escaping (PurchaseResult) -> Void) {
        self.logEvent?(PaywallCheckoutStartedEvent(paywallID: paywallID))
        Adapty.makePurchase(product: product) { purchaseResult in
            switch purchaseResult {
            case .success(let result):
                if result.isPurchaseCancelled {
                    completion(.cancel)
                    self.logEvent?(PurchaseEvent.cancel(iap: (product.vendorProductId, Float(truncating: product.price as NSNumber))))
                    self.logEvent?(PaywallCheckoutCancelledEvent(paywallID: paywallID))
                } else {
                    self.isSubActive = true
                    completion(.success)
                }
            case .failure(let error):
                if error.errorCode == AdaptyError.ErrorCode.paymentCancelled.rawValue {
                    self.logEvent?(PurchaseEvent.cancel(iap: (product.vendorProductId, Float(truncating: product.price as NSNumber))))
                    self.logEvent?(PaywallCheckoutCancelledEvent(paywallID: paywallID))
                    completion(.cancel)
                } else {
                    self.logEvent?(PurchaseEvent.fail(iap: (product.vendorProductId, error)))
                    completion(.fail)
                }
            }
        }
    }

    @MainActor public func restore(_ completion: @escaping (Bool) -> Void) {
        Adapty.restorePurchases { restoreResults in
            switch restoreResults {
            case .success(let profile):
                let hasSub = profile.accessLevels["premium"]?.isActive ?? false
                completion(hasSub)
            case .failure:
                completion(false)
            }
        }
    }
    
    func verifySubscriptionIfNeeded() async {
        do {
            let profile = try await Adapty.getProfile()
            let hasSub = profile.accessLevels["premium"]?.isActive ?? false
            self.isSubActive = hasSub
        } catch {
            Log.printLog(l: .error, str: "Failed to verify subscription: \(error.localizedDescription)")
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
