import Foundation
import StoreKit
import Combine
import Adapty

// MARK: - Protocol

/// Describes the public interface for managing in-app purchases and subscription state.
///
/// Implementations are expected to:
/// - Track the current `subscriptionStatus` and expose it as a reactive stream.
/// - Handle purchases via both the Adapty SDK and the native StoreKit API.
/// - Restore previously completed purchases.
/// - Periodically re-verify entitlements to stay in sync with the App Store / Adapty.
public protocol PurchaseServiceProtocol: AnyObject {

    /// The in-app purchase descriptors known to the service.
    ///
    /// Set this before any purchase or verification call so the service knows which
    /// product identifiers belong to premium access.
    var iaps: [any IAPProtocol] { get set }

    /// The current subscription status, persisted across app launches via `UserDefaults`.
    var subscriptionStatus: SubscriptionStatus { get set }

    /// A publisher that emits the latest `SubscriptionStatus` on every change,
    /// starting with the current value immediately on subscription.
    var subscriptionStatusStream: AnyPublisher<SubscriptionStatus, Never> { get }

    /// Initiates a purchase through the Adapty SDK for a product shown on a paywall.
    ///
    /// - Parameters:
    ///   - product: The Adapty-wrapped product to purchase.
    ///   - paywallID: Identifier of the originating paywall, used for analytics events.
    ///   - completion: Called on the main thread with the purchase outcome.
    func purchaseAdaptyProduct(
        _ product: AdaptyPaywallProduct,
        paywallID: String,
        _ completion: @escaping (PurchaseResult) -> Void
    )

    /// Initiates a purchase through the legacy `SKPayment` API.
    ///
    /// - Parameters:
    ///   - product: The `SKProduct` to purchase.
    ///   - completion: Called on the main thread with the purchase outcome.
    func purchaseProduct(
        _ product: SKProduct,
        _ completion: @escaping (PurchaseResult) -> Void
    )

    /// Restores previously completed transactions and updates the subscription status.
    ///
    /// - Parameter completion: Called on the main thread with `true` if an active
    ///   subscription was found after restore, `false` otherwise.
    func restore(_ completion: @escaping (Bool) -> Void)

    /// Re-verifies the user's subscription entitlements if they might be stale.
    ///
    /// The verification strategy depends on `usesStoreKitEntitlementsForAccess`:
    /// - `false` (default): queries Adapty only.
    /// - `true` (China region): queries StoreKit first, then syncs with Adapty.
    func verifySubscriptionIfNeeded() async
}

// MARK: - Implementation

/// Concrete implementation of `PurchaseServiceProtocol` that bridges Adapty and the
/// native StoreKit 2 API.
///
/// ## Dual-backend entitlement strategy
///
/// The service supports two modes controlled by `usesStoreKitEntitlementsForAccess`:
///
/// - **Adapty mode** (default): Adapty is the source of truth. Transactions are
///   reported to Adapty and subscription state is derived from the Adapty profile.
///
/// - **StoreKit mode** (China region): StoreKit is the source of truth because Adapty
///   may be unreachable. The subscription state is computed directly from StoreKit
///   product status and current entitlements. Adapty is still notified in the
///   background so that server-side analytics remain accurate, but access decisions
///   do not depend on Adapty being reachable.
///
/// ## Transaction listener
///
/// A long-lived `Task` listens to `StoreKit.Transaction.updates` for the lifetime of
/// this object. This ensures that transactions delivered outside the normal purchase
/// flow (e.g. subscription renewals, promotional offers, StoreKit testing) are handled
/// automatically.
class PurchaseService: PurchaseServiceProtocol {

    // MARK: - Public properties

    public var iaps: [any IAPProtocol] = []

    /// Analytics event hook. Set by the owning service to forward purchase-related
    /// events to the analytics pipeline without creating a hard dependency on it.
    var logEvent: ((EventProtocol) -> Void)?

    /// When `true`, subscription access is derived from StoreKit entitlements rather
    /// than the Adapty profile. Set to `true` for Chinese App Store users.
    var usesStoreKitEntitlementsForAccess = false

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

    // MARK: - Private properties

    /// Backing subject for `subscriptionStatusStream`. Seeded with the persisted value
    /// so subscribers always receive the last known status immediately.
    private let subscriptionStatusRelay = CurrentValueSubject<SubscriptionStatus, Never>(UserDefaults.standard.subscriptionStatus)

    /// Holds the background task that monitors `StoreKit.Transaction.updates`.
    /// Cancelled on `deinit` to avoid leaking the task after the service is released.
    private var transactionUpdatesTask: Task<Void, Never>?

    // MARK: - Init / deinit

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
        purchaseAdaptyProduct(
            product,
            paywallID: paywallID,
            placement: paywallID,
            completion
        )
    }

    /// Extended variant used internally when the placement identifier differs from the
    /// paywall identifier (e.g. multi-placement paywalls).
    func purchaseAdaptyProduct(
        _ product: AdaptyPaywallProduct,
        paywallID: String,
        placement: String,
        _ completion: @escaping (PurchaseResult) -> Void
    ) {
        logEvent?(PaywallCheckoutStartedEvent(paywallID: paywallID))

        Adapty.makePurchase(product: product) { [weak self] purchaseResult in
            guard let self else { return }

            switch purchaseResult {
            case .success(let result):
                if result.isPurchaseCancelled {
                    self.handlePurchaseCancelled(
                        product: product,
                        paywallID: paywallID,
                        placement: placement,
                        completion: completion
                    )
                } else {
                    if let profile = result.profile {
                        self.updateSubscriptionState(from: profile)
                    }
                    self.logEvent?(
                        PurchaseEvent.success(
                            iap: (
                                product.vendorProductId,
                                Float(truncating: product.price as NSNumber)
                            )
                        )
                    )
                    completion(.success)
                }
            case .failure(let error):
                self.handlePurchaseFailure(
                    error: error,
                    product: product,
                    paywallID: paywallID,
                    placement: placement,
                    completion: completion
                )
            }
        }
    }

    /// Purchases a product via the legacy `SKPayment` API (used in StoreKit mode /
    /// China region). Internally bridges to the async StoreKit 2 `purchase()` call.
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

    /// Restores purchases, choosing the verification strategy based on
    /// `usesStoreKitEntitlementsForAccess`.
    ///
    /// In StoreKit mode:
    /// 1. `AppStore.sync()` is called to reconcile the local receipt with Apple's
    ///    servers.
    /// 2. Subscription state is derived directly from StoreKit entitlements.
    /// 3. Adapty is notified in the background (best-effort) so server-side data
    ///    stays consistent.
    ///
    /// In Adapty mode: `Adapty.restorePurchases()` is the sole source of truth.
    @MainActor
    public func restore(_ completion: @escaping (Bool) -> Void) {
        if usesStoreKitEntitlementsForAccess {
            Task { [weak self] in
                guard let self else { return }

                await self.syncStoreKitPurchasesForRestore()
                let storeKitStatus = await self.refreshSubscriptionStateFromStoreKit()
                self.restorePurchasesWithAdapty(storeKitStatus: storeKitStatus)
                await MainActor.run {
                    completion(storeKitStatus.isSubActive)
                }
            }
            return
        }

        restorePurchasesWithAdapty(completion: completion)
    }

    /// Calls `Adapty.restorePurchases()` and merges the result with an optional
    /// StoreKit-derived status.
    ///
    /// - Parameters:
    ///   - storeKitStatus: When provided (StoreKit mode), its active state can override
    ///     the Adapty status if the two sources disagree.
    ///   - completion: Optional callback with `true` when an active sub is found.
    private func restorePurchasesWithAdapty(
        storeKitStatus: SubscriptionStatus? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        Adapty.restorePurchases { [weak self] restoreResults in
            switch restoreResults {
            case .success(let profile):
                let status = self?.updateSubscriptionState(from: profile, storeKitStatus: storeKitStatus) ?? .inactive
                completion?(status.isSubActive)
            case .failure(let error):
                let metadata = PaywallFailureMetadata(error: error)
                self?.logEvent?(
                    RestoreFailedEvent(
                        reason: metadata.reason,
                        errorDomain: metadata.errorDomain,
                        errorCode: metadata.errorCode
                    )
                )
                completion?(false)
            }
        }
    }

    // MARK: - Verify

    /// Re-fetches the subscription state from the appropriate source(s).
    ///
    /// In StoreKit mode, StoreKit is queried first and the result is passed along when
    /// Adapty is subsequently polled, allowing the merger logic in
    /// ``resolvedSubscriptionStatus(adaptyStatus:storeKitStatus:)`` to produce the
    /// correct combined status.
    func verifySubscriptionIfNeeded() async {
        if usesStoreKitEntitlementsForAccess {
            let storeKitStatus = await refreshSubscriptionStateFromStoreKit()
            await refreshSubscriptionStateFromAdapty(storeKitStatus: storeKitStatus)
        } else {
            await refreshSubscriptionStateFromAdapty()
        }
    }

    // MARK: - Private – subscription state

    /// Derives the subscription status from an `AdaptyProfile`, optionally merged with
    /// a StoreKit status, then persists and broadcasts it.
    ///
    /// - Returns: The resolved status after the merge.
    @discardableResult
    private func updateSubscriptionState(
        from profile: AdaptyProfile,
        storeKitStatus: SubscriptionStatus? = nil
    ) -> SubscriptionStatus {
        let accessLevel = profile.accessLevels["premium"]
        let status = resolvedSubscriptionStatus(
            adaptyStatus: accessLevel?.subscriptionStatus ?? .inactive,
            storeKitStatus: storeKitStatus
        )
        updateSubscriptionState(status)
        return status
    }

    /// Persists the status and broadcasts it on the main queue.
    private func updateSubscriptionState(_ status: SubscriptionStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.subscriptionStatus = status
        }
    }

    /// Merges the Adapty-derived status with the StoreKit-derived status.
    ///
    /// The merge rules favour access: if either source reports an active subscription
    /// the StoreKit status is used as the authoritative value. When both agree that
    /// the subscription is inactive, the Adapty status is returned so its richer
    /// metadata (e.g. exact expiry) is preserved.
    ///
    /// - Parameters:
    ///   - adaptyStatus: Status derived from the Adapty profile.
    ///   - storeKitStatus: Status derived from StoreKit, or `nil` in Adapty-only mode.
    private func resolvedSubscriptionStatus(
        adaptyStatus: SubscriptionStatus,
        storeKitStatus: SubscriptionStatus?
    ) -> SubscriptionStatus {
        guard let storeKitStatus else {
            return adaptyStatus
        }

        switch (storeKitStatus.isSubActive, adaptyStatus.isSubActive) {
        case (true, true):
            return adaptyStatus
        case (true, false), (false, true):
            return storeKitStatus
        case (false, false):
            return adaptyStatus
        }
    }

    // MARK: - Private – StoreKit status resolution

    /// Queries StoreKit for the subscription status across all known product IDs,
    /// updates the persisted status, and returns the result.
    ///
    /// Two independent data sources are consulted and merged:
    /// - ``subscriptionStatusFromStoreKitProducts(_:)`` — uses the StoreKit 2
    ///   `subscription.status` API which includes grace period and billing retry states.
    /// - ``subscriptionStatusFromCurrentEntitlements(productIdentifiers:)`` — iterates
    ///   `Transaction.currentEntitlements` as a fallback when the product-level status
    ///   cannot be loaded.
    @discardableResult
    private func refreshSubscriptionStateFromStoreKit() async -> SubscriptionStatus {
        let productIdentifiers = Set(iaps.map(\.productID))
        guard !productIdentifiers.isEmpty else {
            updateSubscriptionState(.inactive)
            return .inactive
        }

        let subscriptionStatus = await subscriptionStatusFromStoreKitProducts(productIdentifiers)
        let fallbackStatus = await subscriptionStatusFromCurrentEntitlements(productIdentifiers: productIdentifiers)
        let status = resolvedStoreKitStatus(
            subscriptionStatus: subscriptionStatus,
            fallbackStatus: fallbackStatus
        )

        updateSubscriptionState(status)
        return status
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

    // MARK: - Private – StoreKit purchase flow

    /// Calls `AppStore.sync()` to reconcile the local receipt with Apple's servers
    /// before a restore operation. Errors are logged and emitted as analytics events
    /// but do not block the restore flow.
    private func syncStoreKitPurchasesForRestore() async {
        do {
            try await AppStore.sync()
        } catch {
            let metadata = AnalyticsErrorMetadata(error: error)
            logEvent?(
                RestoreFailedEvent(
                    reason: "storekit_sync_failed",
                    errorDomain: metadata.errorDomain,
                    errorCode: metadata.errorCode
                )
            )
            Log.printLog(l: .error, str: "Failed to sync StoreKit purchases: \(error.localizedDescription)")
        }
    }

    /// Fetches the StoreKit 2 `Product` for the given identifier and initiates a
    /// purchase. Returns `.fail` if the product cannot be loaded.
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

    /// Calls `product.purchase()` and maps the StoreKit 2 result to a `PurchaseResult`.
    ///
    /// Verified transactions are forwarded to ``handleVerifiedTransaction(_:)`` for
    /// entitlement processing. Unverified transactions and pending states are treated
    /// as failures; user cancellation is surfaced as `.cancel`.
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

    // MARK: - Private – transaction handling

    /// Starts a long-lived background `Task` that listens to `Transaction.updates`.
    ///
    /// This observer handles renewals, refunds, and other App Store-driven transaction
    /// events that arrive outside the normal purchase flow. The task is cancelled on
    /// `deinit`.
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

    /// Processes a verified StoreKit transaction, updating subscription state and
    /// finishing the transaction.
    ///
    /// Behaviour differs by mode:
    /// - **StoreKit mode**: StoreKit is queried for the authoritative status, the
    ///   transaction is finished immediately, then Adapty is notified in the background.
    /// - **Adapty mode**: The transaction is reported to Adapty first; the subscription
    ///   state is updated from the returned Adapty profile before the transaction is
    ///   finished.
    ///
    /// - Returns: `true` if the transaction was successfully processed and finished.
    private func handleVerifiedTransaction(_ transaction: StoreKit.Transaction) async -> Bool {
        if usesStoreKitEntitlementsForAccess {
            let storeKitStatus = await refreshSubscriptionStateFromStoreKit()
            await transaction.finish()
            syncTransactionToAdapty(transaction, storeKitStatus: storeKitStatus)
            return true
        }

        guard await reportTransactionToAdapty(transaction) else {
            return false
        }

        await refreshSubscriptionStateFromAdapty()
        await transaction.finish()
        return true
    }

    /// Fetches the latest Adapty profile and updates the subscription state.
    ///
    /// When called in StoreKit mode the `storeKitStatus` is passed through so the
    /// merger logic can produce the correct combined status.
    private func refreshSubscriptionStateFromAdapty(storeKitStatus: SubscriptionStatus? = nil) async {
        do {
            let profile = try await Adapty.getProfile()
            updateSubscriptionState(from: profile, storeKitStatus: storeKitStatus)
        } catch {
            Log.printLog(l: .error, str: "Failed to verify subscription: \(error.localizedDescription)")
        }
    }

    /// Reports a StoreKit transaction to Adapty in the background (fire-and-forget).
    ///
    /// Used in StoreKit mode to keep Adapty's server-side data consistent without
    /// blocking access decisions on Adapty's availability.
    private func syncTransactionToAdapty(
        _ transaction: StoreKit.Transaction,
        storeKitStatus: SubscriptionStatus
    ) {
        Task { [weak self] in
            guard let self,
                  await self.reportTransactionToAdapty(transaction) else {
                return
            }

            await self.refreshSubscriptionStateFromAdapty(storeKitStatus: storeKitStatus)
        }
    }

    /// Calls `Adapty.reportTransaction(_:withVariationId:)` and returns whether it
    /// succeeded.
    private func reportTransactionToAdapty(_ transaction: StoreKit.Transaction) async -> Bool {
        do {
            try await Adapty.reportTransaction(transaction, withVariationId: nil)
            return true
        } catch {
            Log.printLog(l: .error, str: "Failed to report StoreKit transaction to Adapty: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private – purchase event helpers

    /// Handles the user cancelling an Adapty purchase by logging the appropriate
    /// analytics events and forwarding `.cancel` to the completion handler.
    private func handlePurchaseCancelled(
        product: AdaptyPaywallProduct,
        paywallID: String,
        placement: String,
        completion: @escaping (PurchaseResult) -> Void
    ) {
        let metadata = PaywallFailureMetadata.cancelled
        logEvent?(PurchaseEvent.cancel(iap: (product.vendorProductId, Float(truncating: product.price as NSNumber))))
        logEvent?(PaywallCheckoutCancelledEvent(paywallID: paywallID))
        logEvent?(
            PurchaseFailedEvent(
                reason: metadata.reason,
                productID: product.vendorProductId,
                placement: placement,
                errorDomain: metadata.errorDomain,
                errorCode: metadata.errorCode
            )
        )
        completion(.cancel)
    }

    /// Handles a non-cancellation failure from an Adapty purchase.
    ///
    /// Adapty maps payment cancellations to an error with code
    /// `paymentCancelled`, so this method delegates to ``handlePurchaseCancelled``
    /// when that specific code is detected, avoiding duplicate event logging.
    private func handlePurchaseFailure(
        error: AdaptyError,
        product: AdaptyPaywallProduct,
        paywallID: String,
        placement: String,
        completion: @escaping (PurchaseResult) -> Void
    ) {
        if error.errorCode == AdaptyError.ErrorCode.paymentCancelled.rawValue {
            handlePurchaseCancelled(
                product: product,
                paywallID: paywallID,
                placement: placement,
                completion: completion
            )
        } else {
            let metadata = PaywallFailureMetadata(error: error)
            logEvent?(PurchaseEvent.fail(iap: (product.vendorProductId, error)))
            logEvent?(
                PurchaseFailedEvent(
                    reason: metadata.reason,
                    productID: product.vendorProductId,
                    placement: placement,
                    errorDomain: metadata.errorDomain,
                    errorCode: metadata.errorCode
                )
            )
            completion(.fail)
        }
    }
}

// MARK: - PaywallFailureMetadata

/// Normalises Adapty errors into a flat, analytics-friendly representation.
///
/// The `reason` string is a short key suitable for grouping related failures in
/// dashboards (e.g. `"cancelled"`, `"network_error"`, `"payment_invalid"`). The
/// domain and code are forwarded verbatim from the underlying `NSError` so that
/// support tooling can cross-reference them with App Store Connect.
struct PaywallFailureMetadata {
    let reason: String
    let errorDomain: String
    let errorCode: Int

    init(error: AdaptyError) {
        let nsError = error as NSError
        self.reason = Self.reason(error: error, nsError: nsError)
        self.errorDomain = nsError.domain
        self.errorCode = error.errorCode
    }

    private init(reason: String, errorDomain: String, errorCode: Int) {
        self.reason = reason
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }

    /// Pre-built metadata for a user-initiated cancellation.
    static var cancelled: PaywallFailureMetadata {
        PaywallFailureMetadata(
            reason: "cancelled",
            errorDomain: "AdaptyError",
            errorCode: AdaptyError.ErrorCode.paymentCancelled.rawValue
        )
    }

    private static func reason(error: AdaptyError, nsError: NSError) -> String {
        if error.errorCode == AdaptyError.ErrorCode.paymentCancelled.rawValue {
            return "cancelled"
        } else if isNetworkError(nsError) {
            return "network_error"
        } else {
            return "payment_invalid"
        }
    }

    /// Recursively checks `NSError.userInfo[NSUnderlyingErrorKey]` to detect network
    /// errors that may be wrapped inside an Adapty error.
    private static func isNetworkError(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain {
            return true
        }

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isNetworkError(underlyingError)
        }

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? Error {
            return isNetworkError(underlyingError as NSError)
        }

        return false
    }
}

// MARK: - UserDefaults + SubscriptionStatus

extension UserDefaults {

    private static let subscriptionStatusKey = "subscriptionStatus"

    /// Persists and restores `SubscriptionStatus` using JSON coding.
    ///
    /// Returns `.inactive` when no value has been stored yet or when decoding fails,
    /// which is the safe default for new installs or data migrations.
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
