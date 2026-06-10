enum StoreKitPurchaseOutcome {
    case success
    case cancelled
    case failed(errorDomain: String, errorCode: Int, description: String)

    static let errorDomain = "AwebAnalyticsService.StoreKit"
    static let paymentsUnavailableCode = -200
    static let productNotFoundCode = -201
    static let unverifiedTransactionCode = -202
    static let pendingPurchaseCode = -203
    static let unknownPurchaseResultCode = -204
    static let transactionProcessingFailedCode = -205

    var purchaseResult: PurchaseResult {
        switch self {
        case .success:
            return .success
        case .cancelled:
            return .cancel
        case .failed:
            return .fail
        }
    }
}
