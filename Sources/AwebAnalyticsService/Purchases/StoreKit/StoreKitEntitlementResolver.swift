import Foundation
import StoreKit

struct StoreKitEntitlementResolver {

    /// Queries StoreKit for the subscription status across all known product IDs.
    ///
    /// Two independent data sources are consulted and merged:
    /// - ``subscriptionStatusFromStoreKitProducts(_:)`` — uses the StoreKit 2
    ///   `subscription.status` API which includes grace period and billing retry states.
    /// - ``subscriptionStatusFromCurrentEntitlements(productIdentifiers:)`` — iterates
    ///   `Transaction.currentEntitlements` as a fallback when the product-level status
    ///   cannot be loaded.
    func resolveStatus(for productIdentifiers: Set<String>) async -> SubscriptionStatus {
        guard !productIdentifiers.isEmpty else {
            return .inactive
        }

        let subscriptionStatus = await subscriptionStatusFromStoreKitProducts(productIdentifiers)
        let fallbackStatus = await subscriptionStatusFromCurrentEntitlements(productIdentifiers: productIdentifiers)
        return resolvedStoreKitStatus(
            subscriptionStatus: subscriptionStatus,
            fallbackStatus: fallbackStatus
        )
    }

    /// Loads StoreKit products and iterates their subscription statuses.
    ///
    /// When multiple statuses are present (e.g. family sharing, multiple devices), the
    /// one with the highest priority is kept via ``preferredStoreKitStatus(_:_:)``.
    ///
    /// - Returns: The best available status, or `nil` if the products could not be
    ///   loaded (e.g. network error).
    private func subscriptionStatusFromStoreKitProducts(
        _ productIdentifiers: Set<String>
    ) async -> SubscriptionStatus? {
        do {
            let products = try await StoreKit.Product.products(for: productIdentifiers)
            var resolvedStatus: SubscriptionStatus?

            for product in products {
                guard productIdentifiers.contains(product.id),
                      let subscription = product.subscription else {
                    continue
                }

                let statuses = try await subscription.status
                for status in statuses {
                    guard let subscriptionStatus = subscriptionStatus(
                        from: status,
                        productIdentifiers: productIdentifiers
                    ) else {
                        continue
                    }

                    resolvedStatus = preferredStoreKitStatus(
                        resolvedStatus,
                        subscriptionStatus
                    )
                }
            }

            return resolvedStatus
        } catch {
            Log.printLog(l: .error, str: "Failed to load StoreKit subscription status: \(error.localizedDescription)")
            return nil
        }
    }

    /// Maps a single StoreKit `SubscriptionInfo.Status` to a `SubscriptionStatus`.
    ///
    /// Returns `nil` when the transaction cannot be verified or when the product ID is
    /// not in the managed set, so unrelated transactions are silently skipped.
    private func subscriptionStatus(
        from status: StoreKit.Product.SubscriptionInfo.Status,
        productIdentifiers: Set<String>
    ) -> SubscriptionStatus? {
        guard case .verified(let transaction) = status.transaction,
              productIdentifiers.contains(transaction.productID) else {
            return nil
        }

        switch status.state {
        case .subscribed:
            return .active
        case .inGracePeriod:
            return .activeBillingIssue(expiresAt: gracePeriodExpirationDate(from: status))
        case .inBillingRetryPeriod:
            return .inactiveDueToBilling
        case .expired, .revoked:
            return .inactive
        default:
            return nil
        }
    }

    /// Extracts the grace period expiration date from a subscription status's renewal
    /// info, if available.
    private func gracePeriodExpirationDate(
        from status: StoreKit.Product.SubscriptionInfo.Status
    ) -> Date? {
        guard case .verified(let renewalInfo) = status.renewalInfo else {
            return nil
        }

        return renewalInfo.gracePeriodExpirationDate
    }

    /// Iterates `Transaction.currentEntitlements` and returns `.active` if any
    /// non-expired, non-revoked transaction is found for the managed product IDs.
    ///
    /// Used as a fallback when the product-level subscription status API fails.
    private func subscriptionStatusFromCurrentEntitlements(
        productIdentifiers: Set<String>
    ) async -> SubscriptionStatus {
        for await verificationResult in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = verificationResult,
                  productIdentifiers.contains(transaction.productID),
                  isActiveEntitlement(transaction) else {
                continue
            }

            return .active
        }

        return .inactive
    }

    /// Resolves the final StoreKit status from the primary and fallback sources.
    ///
    /// The primary status is preferred when both are available; the fallback is used
    /// when the primary could not be determined (e.g. due to a network error).
    private func resolvedStoreKitStatus(
        subscriptionStatus: SubscriptionStatus?,
        fallbackStatus: SubscriptionStatus
    ) -> SubscriptionStatus {
        guard let subscriptionStatus else {
            return fallbackStatus
        }

        return preferredStoreKitStatus(subscriptionStatus, fallbackStatus)
    }

    /// Returns whichever of the two statuses has the higher priority, preferring
    /// `newStatus` on a tie.
    ///
    /// Priority (highest first): `.activeBillingIssue` > `.active` >
    /// `.inactiveDueToBilling` > `.inactive`.
    private func preferredStoreKitStatus(
        _ currentStatus: SubscriptionStatus?,
        _ newStatus: SubscriptionStatus
    ) -> SubscriptionStatus {
        guard let currentStatus else {
            return newStatus
        }

        return storeKitStatusPriority(newStatus) > storeKitStatusPriority(currentStatus)
            ? newStatus
            : currentStatus
    }

    /// Numeric priority used to compare subscription statuses.
    ///
    /// Higher values win in ``preferredStoreKitStatus(_:_:)``. Grace-period access
    /// ranks highest because the user should retain access even when payment is
    /// temporarily failing.
    private func storeKitStatusPriority(_ status: SubscriptionStatus) -> Int {
        switch status {
        case .activeBillingIssue:
            return 4
        case .active:
            return 3
        case .inactiveDueToBilling:
            return 2
        case .inactive:
            return 1
        }
    }

    /// Returns `true` when a transaction represents a currently valid entitlement.
    ///
    /// A transaction is considered active when it has not been revoked and either has
    /// no expiration date (e.g. non-consumables) or its expiration date is in the
    /// future.
    private func isActiveEntitlement(_ transaction: StoreKit.Transaction) -> Bool {
        if transaction.revocationDate != nil {
            return false
        }

        if let expirationDate = transaction.expirationDate {
            return expirationDate > Date()
        }

        return true
    }
}
