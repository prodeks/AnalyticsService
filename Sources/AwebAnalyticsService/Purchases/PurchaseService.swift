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
    
    public func purchaseAdaptyProduct(_ product: AdaptyPaywallProduct, paywallID: String, _ completion: @escaping (PurchaseResult) -> Void) {
        self.logEvent?(PaywallCheckoutStartedEvent(paywallID: paywallID))
        Adapty.makePurchase(product: product) { purchaseResult in
            switch purchaseResult {
            case .success:
                self.isSubActive = true
                completion(.success)
            case .failure(let error):
                var productIdentifier: String {
                    if let sk2 = product.sk2Product {
                        return sk2.id
                    } else {
                        return product.sk1Product?.productIdentifier ?? ""
                    }
                }
                
                var price: Float {
                    if let sk2 = product.sk2Product {
                        return Float(truncating: sk2.price as NSNumber)
                    } else {
                        return product.sk1Product?.price.floatValue ?? 0
                    }
                }
                
                if error.errorCode == AdaptyError.ErrorCode.paymentCancelled.rawValue {
                    self.logEvent?(PurchaseEvent.cancel(iap: (productIdentifier, price)))
                    self.logEvent?(PaywallCheckoutCancelledEvent(paywallID: paywallID))
                    completion(.cancel)
                } else {
                    self.logEvent?(PurchaseEvent.fail(iap: (productIdentifier, error)))
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
        if let profile = try? await Adapty.getProfile() {
            let hasSub = profile.accessLevels["premium"]?.isActive ?? false
            self.isSubActive = hasSub
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
