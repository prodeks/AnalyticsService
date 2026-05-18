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
    func purchaseProduct(
        _ product: SKProduct,
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
    private var transactionUpdatesTask: Task<Void, Never>?
    
    init() {
        startTransactionUpdatesListener()
    }
    
    deinit {
        transactionUpdatesTask?.cancel()
    }
    
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
    
    public func purchaseProduct(
        _ product: SKProduct,
        _ completion: @escaping (PurchaseResult) -> Void
    ) {
        guard SKPaymentQueue.canMakePayments() else {
            completion(.fail)
            return
        }
        
        let productIdentifier = product.productIdentifier
        Task { [weak self] in
            guard let self else { return }
            
            let result = await self.purchaseProduct(with: productIdentifier)
            await MainActor.run {
                completion(result)
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
        await refreshSubscriptionStateFromAdapty()
    }
    
    // MARK: - Private
    
    private func updateSubscriptionState(from profile: AdaptyProfile) {
        let accessLevel = profile.accessLevels["premium"]
        subscriptionStatus = accessLevel?.subscriptionStatus ?? .inactive
    }
    
    private func purchaseProduct(with productIdentifier: String) async -> PurchaseResult {
        do {
            guard let product = try await StoreKit.Product.products(for: [productIdentifier]).first else {
                return .fail
            }
            
            return await purchase(product)
        } catch {
            Log.printLog(l: .error, str: "Failed to load StoreKit product: \(error.localizedDescription)")
            return .fail
        }
    }
    
    private func purchase(_ product: StoreKit.Product) async -> PurchaseResult {
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verificationResult):
                switch verificationResult {
                case .verified(let transaction):
                    guard await handleVerifiedTransaction(transaction) else {
                        return .fail
                    }
                    
                    return .success
                case .unverified(_, _):
                    return .fail
                }
            case .userCancelled:
                return .cancel
            case .pending:
                return .fail
            @unknown default:
                return .fail
            }
        } catch {
            Log.printLog(l: .error, str: "Failed to purchase StoreKit product: \(error.localizedDescription)")
            return .fail
        }
    }
    
    private func startTransactionUpdatesListener() {
        transactionUpdatesTask = Task { [weak self] in
            for await verificationResult in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                
                switch verificationResult {
                case .verified(let transaction):
                    _ = await self?.handleVerifiedTransaction(transaction)
                case .unverified(_, _):
                    break
                }
            }
        }
    }
    
    private func handleVerifiedTransaction(_ transaction: StoreKit.Transaction) async -> Bool {
        guard await reportTransactionToAdapty(transaction) else {
            return false
        }
        
        await refreshSubscriptionStateFromAdapty()
        await transaction.finish()
        return true
    }
    
    private func refreshSubscriptionStateFromAdapty() async {
        do {
            let profile = try await Adapty.getProfile()
            updateSubscriptionState(from: profile)
        } catch {
            Log.printLog(l: .error, str: "Failed to verify subscription: \(error.localizedDescription)")
        }
    }
    
    private func reportTransactionToAdapty(_ transaction: StoreKit.Transaction) async -> Bool {
        do {
            try await Adapty.reportTransaction(transaction, withVariationId: nil)
            return true
        } catch {
            Log.printLog(l: .error, str: "Failed to report StoreKit transaction to Adapty: \(error.localizedDescription)")
            return false
        }
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
