import Foundation
import StoreKit
import Combine
import Adapty

public protocol PurchaseServiceProtocol: AnyObject {
    var iaps: [any IAPProtocol] { get set }
    var subscriptionStatus: SubscriptionStatus { get set }
    var subscriptionStatusStream: AnyPublisher<SubscriptionStatus, Never> { get }
    
    func purchaseAdaptyProduct(
        _ product: AdaptyPaywallProduct,
        paywallID: String,
        _ completion: @escaping (PurchaseResult) -> Void
    )
    func restore(_ completion: @escaping (Bool) -> Void)
    func verifySubscriptionIfNeeded() async
}

class PurchaseService: PurchaseServiceProtocol {
    
    public var iaps: [any IAPProtocol] = []
    
    var logEvent: ((EventProtocol) -> Void)?
    
    public var subscriptionStatus: SubscriptionStatus {
        get { UserDefaults.standard.subscriptionStatus }
        set {
            UserDefaults.standard.subscriptionStatus = newValue
            subscriptionStatusRelay.send(newValue)
        }
    }
    
    public var subscriptionStatusStream: AnyPublisher<SubscriptionStatus, Never> {
        subscriptionStatusRelay.eraseToAnyPublisher()
    }
    
    private let subscriptionStatusRelay = CurrentValueSubject<SubscriptionStatus, Never>(UserDefaults.standard.subscriptionStatus)
    
    // MARK: - Purchase
    
    public func purchaseAdaptyProduct(
        _ product: AdaptyPaywallProduct,
        paywallID: String,
        _ completion: @escaping (PurchaseResult) -> Void
    ) {
        logEvent?(PaywallCheckoutStartedEvent(paywallID: paywallID))
        
        Adapty.makePurchase(product: product) { [weak self] purchaseResult in
            guard let self else { return }
            
            switch purchaseResult {
            case .success(let result):
                if result.isPurchaseCancelled {
                    self.handlePurchaseCancelled(product: product, paywallID: paywallID, completion: completion)
                } else {
                    if let profile = result.profile {
                        self.updateSubscriptionState(from: profile)
                    }
                    completion(.success)
                }
            case .failure(let error):
                self.handlePurchaseFailure(error: error, product: product, paywallID: paywallID, completion: completion)
            }
        }
    }
    
    // MARK: - Restore
    
    @MainActor
    public func restore(_ completion: @escaping (Bool) -> Void) {
        Adapty.restorePurchases { [weak self] restoreResults in
            switch restoreResults {
            case .success(let profile):
                self?.updateSubscriptionState(from: profile)
                let hasSub = profile.accessLevels["premium"]?.isActive ?? false
                completion(hasSub)
            case .failure:
                completion(false)
            }
        }
    }
    
    // MARK: - Verify
    
    func verifySubscriptionIfNeeded() async {
        do {
            let profile = try await Adapty.getProfile()
            updateSubscriptionState(from: profile)
        } catch {
            Log.printLog(l: .error, str: "Failed to verify subscription: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private
    
    private func updateSubscriptionState(from profile: AdaptyProfile) {
        let accessLevel = profile.accessLevels["premium"]
        subscriptionStatus = accessLevel?.subscriptionStatus ?? .inactive
    }
    
    private func handlePurchaseCancelled(product: AdaptyPaywallProduct, paywallID: String, completion: @escaping (PurchaseResult) -> Void) {
        logEvent?(PurchaseEvent.cancel(iap: (product.vendorProductId, Float(truncating: product.price as NSNumber))))
        logEvent?(PaywallCheckoutCancelledEvent(paywallID: paywallID))
        completion(.cancel)
    }
    
    private func handlePurchaseFailure(error: AdaptyError, product: AdaptyPaywallProduct, paywallID: String, completion: @escaping (PurchaseResult) -> Void) {
        if error.errorCode == AdaptyError.ErrorCode.paymentCancelled.rawValue {
            handlePurchaseCancelled(product: product, paywallID: paywallID, completion: completion)
        } else {
            logEvent?(PurchaseEvent.fail(iap: (product.vendorProductId, error)))
            completion(.fail)
        }
    }
}

extension UserDefaults {
    private static let subscriptionStatusKey = "subscriptionStatus"
    
    var subscriptionStatus: SubscriptionStatus {
        get {
            guard let data = data(forKey: Self.subscriptionStatusKey),
                  let status = try? JSONDecoder().decode(SubscriptionStatus.self, from: data) else {
                return .inactive
            }
            return status
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, forKey: Self.subscriptionStatusKey)
            }
        }
    }
}
