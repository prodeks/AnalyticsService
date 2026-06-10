import StoreKit

final class TransactionObserver {

    private var task: Task<Void, Never>?

    init(handleTransaction: @escaping (StoreKit.Transaction) async -> Void) {
        task = Task {
            for await verificationResult in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }

                switch verificationResult {
                case .verified(let transaction):
                    await handleTransaction(transaction)
                case .unverified(_, _):
                    break
                }
            }
        }
    }

    deinit {
        task?.cancel()
    }
}
