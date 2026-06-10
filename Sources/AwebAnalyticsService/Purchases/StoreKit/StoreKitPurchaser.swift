import StoreKit

struct StoreKitPurchaser {

    private let processTransaction: (StoreKit.Transaction) async -> Bool

    init(processTransaction: @escaping (StoreKit.Transaction) async -> Bool) {
        self.processTransaction = processTransaction
    }

    /// Calls `AppStore.sync()` to reconcile the local receipt with Apple's servers
    /// before a restore operation.
    func syncWithAppStore() async throws {
        try await AppStore.sync()
    }

    /// Fetches the StoreKit 2 `Product` for the given identifier and initiates a
    /// purchase. Returns a structured outcome so analytics can capture the failure.
    func purchaseProduct(with productIdentifier: String) async -> StoreKitPurchaseOutcome {
        do {
            guard let product = try await StoreKit.Product.products(for: [productIdentifier]).first else {
                return .failed(
                    errorDomain: StoreKitPurchaseOutcome.errorDomain,
                    errorCode: StoreKitPurchaseOutcome.productNotFoundCode,
                    description: "StoreKit product was not found: \(productIdentifier)"
                )
            }

            return await purchase(product)
        } catch {
            let metadata = AnalyticsErrorMetadata(error: error)
            Log.printLog(l: .error, str: "Failed to load StoreKit product: \(error.localizedDescription)")
            return .failed(
                errorDomain: metadata.errorDomain,
                errorCode: metadata.errorCode,
                description: error.localizedDescription
            )
        }
    }

    /// Calls `product.purchase()` and maps the StoreKit 2 result to a `PurchaseResult`.
    ///
    /// Verified transactions are forwarded for entitlement processing. Unverified
    /// transactions and pending states are treated as failures; user cancellation is
    /// surfaced as `.cancel`.
    private func purchase(_ product: StoreKit.Product) async -> StoreKitPurchaseOutcome {
        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                switch verificationResult {
                case .verified(let transaction):
                    guard await processTransaction(transaction) else {
                        return .failed(
                            errorDomain: StoreKitPurchaseOutcome.errorDomain,
                            errorCode: StoreKitPurchaseOutcome.transactionProcessingFailedCode,
                            description: "StoreKit transaction processing failed"
                        )
                    }

                    return .success
                case .unverified(_, _):
                    return .failed(
                        errorDomain: StoreKitPurchaseOutcome.errorDomain,
                        errorCode: StoreKitPurchaseOutcome.unverifiedTransactionCode,
                        description: "StoreKit transaction could not be verified"
                    )
                }
            case .userCancelled:
                return .cancelled
            case .pending:
                return .failed(
                    errorDomain: StoreKitPurchaseOutcome.errorDomain,
                    errorCode: StoreKitPurchaseOutcome.pendingPurchaseCode,
                    description: "StoreKit purchase is pending"
                )
            @unknown default:
                return .failed(
                    errorDomain: StoreKitPurchaseOutcome.errorDomain,
                    errorCode: StoreKitPurchaseOutcome.unknownPurchaseResultCode,
                    description: "Unknown StoreKit purchase result"
                )
            }
        } catch {
            let metadata = AnalyticsErrorMetadata(error: error)
            Log.printLog(l: .error, str: "Failed to purchase StoreKit product: \(error.localizedDescription)")
            return .failed(
                errorDomain: metadata.errorDomain,
                errorCode: metadata.errorCode,
                description: error.localizedDescription
            )
        }
    }
}
