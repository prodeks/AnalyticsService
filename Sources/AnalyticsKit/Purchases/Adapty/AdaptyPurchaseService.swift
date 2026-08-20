import Adapty
import StoreKit

struct AdaptyPurchaseService {

    func makePurchase(
        product: AdaptyPaywallProduct,
        completion: @escaping @Sendable (Result<AdaptyPurchaseResult, AdaptyError>) -> Void
    ) {
        Adapty.makePurchase(product: product, completion)
    }

    func restorePurchases(
        completion: @escaping @Sendable (Result<AdaptyProfile, AdaptyError>) -> Void
    ) {
        Adapty.restorePurchases(completion)
    }

    func profile() async throws -> AdaptyProfile {
        try await Adapty.getProfile()
    }

    func reportTransaction(_ transaction: StoreKit.Transaction, variationId: String?) async throws {
        try await Adapty.reportTransaction(transaction, withVariationId: variationId)
    }
}
