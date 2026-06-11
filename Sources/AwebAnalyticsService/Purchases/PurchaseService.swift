import Foundation
import StoreKit
import Combine
import Adapty

/// Concrete implementation of `PurchaseServiceProtocol` that coordinates focused
/// purchase, restore, entitlement, and transaction collaborators.
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
        get { statusStore.current }
        set { statusStore.current = newValue }
    }

    public var subscriptionStatusStream: AnyPublisher<SubscriptionStatus, Never> {
        statusStore.stream
    }

    // MARK: - Private properties

    private let statusStore = SubscriptionStatusStore()
    private let entitlementResolver = StoreKitEntitlementResolver()
    private let adaptyService = AdaptyPurchaseService()

    private lazy var storeKitPurchaser = StoreKitPurchaser { [weak self] transaction in
        await self?.handleVerifiedTransaction(transaction) ?? false
    }

    private var transactionObserver: TransactionObserver?

    /// Adapty variation id from the most recent paywall purchase, used when reporting
    /// StoreKit transactions back to Adapty.
    private var pendingVariationId: String?

    // MARK: - Init

    init() {
        transactionObserver = TransactionObserver { [weak self] transaction in
            _ = await self?.handleVerifiedTransaction(transaction)
        }
    }

    // MARK: - Purchase

    public func purchaseAdaptyProduct(
        _ product: AdaptyPaywallProduct,
        paywallID: String,
        presentationID: String?,
        variationId: String?,
        _ completion: @escaping (PurchaseResult) -> Void
    ) {
        purchaseAdaptyProduct(
            product,
            paywallID: paywallID,
            placement: paywallID,
            presentationID: presentationID,
            variationId: variationId,
            completion
        )
    }

    /// Extended variant used internally when the placement identifier differs from the
    /// paywall identifier (e.g. multi-placement paywalls).
    func purchaseAdaptyProduct(
        _ product: AdaptyPaywallProduct,
        paywallID: String,
        placement: String,
        presentationID: String? = nil,
        variationId: String? = nil,
        _ completion: @escaping (PurchaseResult) -> Void
    ) {
        let productContext = AdaptyProductContext(product: product)
        let checkoutContext = PaywallCheckoutContext(
            paywallID: paywallID,
            placement: placement,
            product: productContext,
            variationId: variationId,
            presentationID: presentationID,
            source: .adapty
        )
        pendingVariationId = variationId
        if let logEvent {
            PaywallEventLogger.checkoutStarted(checkoutContext, log: logEvent)
        }

        adaptyService.makePurchase(product: product) { [weak self] purchaseResult in
            guard let self else { return }

            switch purchaseResult {
            case .success(let result):
                if result.isPurchaseCancelled {
                    self.handlePurchaseCancelled(
                        checkoutContext: checkoutContext,
                        completion: completion
                    )
                } else {
                    if let profile = result.profile {
                        self.updateSubscriptionState(from: profile)
                    }
                    if let logEvent = self.logEvent {
                        PaywallEventLogger.purchaseSucceeded(checkoutContext, log: logEvent)
                    }
                    completion(.success)
                }
            case .failure(let error):
                self.handlePurchaseFailure(
                    error: error,
                    checkoutContext: checkoutContext,
                    completion: completion
                )
            }
        }
    }

    public func purchaseProduct(
        _ product: StoreKit.Product,
        paywallID: String,
        placement: String,
        presentationID: String?,
        _ completion: @escaping (PurchaseResult) -> Void
    ) {
        let productContext = StoreKitProductContext(product: product)
        let checkoutContext = PaywallCheckoutContext(
            paywallID: paywallID,
            placement: placement,
            productID: productContext.productID,
            price: productContext.price,
            currency: productContext.currency,
            presentationID: presentationID,
            source: .storeKit
        )

        if let logEvent {
            PaywallEventLogger.checkoutStarted(checkoutContext, log: logEvent)
        }

        guard SKPaymentQueue.canMakePayments() else {
            if let logEvent {
                PaywallEventLogger.purchaseFailed(
                    checkoutContext,
                    reason: .paymentInvalid,
                    errorDomain: StoreKitPurchaseOutcome.errorDomain,
                    errorCode: StoreKitPurchaseOutcome.paymentsUnavailableCode,
                    description: "StoreKit payments are unavailable on this device",
                    log: logEvent
                )
            }
            completion(.fail)
            return
        }

        Task { [weak self] in
            guard let self else { return }

            let outcome = await self.storeKitPurchaser.purchase(product)
            await MainActor.run {
                if let logEvent = self.logEvent {
                    self.logStoreKitOutcome(outcome, context: checkoutContext, log: logEvent)
                }
                completion(outcome.purchaseResult)
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
        let source: PaywallSource = usesStoreKitEntitlementsForAccess ? .storeKit : .adapty
        restore(source: source, completion)
    }

    @MainActor
    public func restore(source: PaywallSource, _ completion: @escaping (Bool) -> Void) {
        if usesStoreKitEntitlementsForAccess {
            Task { [weak self] in
                guard let self else { return }

                await self.syncStoreKitPurchasesForRestore()
                let storeKitStatus = await self.refreshSubscriptionStateFromStoreKit()
                self.restorePurchasesWithAdapty(source: source, storeKitStatus: storeKitStatus)
                await MainActor.run {
                    completion(storeKitStatus.isSubActive)
                }
            }
            return
        }

        restorePurchasesWithAdapty(source: source, completion: completion)
    }

    /// Calls `Adapty.restorePurchases()` and merges the result with an optional
    /// StoreKit-derived status.
    ///
    /// - Parameters:
    ///   - storeKitStatus: When provided (StoreKit mode), its active state can override
    ///     the Adapty status if the two sources disagree.
    ///   - completion: Optional callback with `true` when an active sub is found.
    private func restorePurchasesWithAdapty(
        source: PaywallSource,
        storeKitStatus: SubscriptionStatus? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        adaptyService.restorePurchases { [weak self] restoreResults in
            switch restoreResults {
            case .success(let profile):
                let status = self?.updateSubscriptionState(from: profile, storeKitStatus: storeKitStatus) ?? .inactive
                if let logEvent = self?.logEvent {
                    PaywallEventLogger.restoreSucceeded(source: source, log: logEvent)
                }
                completion?(status.isSubActive)
            case .failure(let error):
                let metadata = PaywallFailureMetadata(error: error)
                if let logEvent = self?.logEvent {
                    PaywallEventLogger.restoreFailed(
                        reason: metadata.reason,
                        source: source,
                        errorDomain: metadata.errorDomain,
                        errorCode: metadata.errorCode,
                        log: logEvent
                    )
                }
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

    /// Queries StoreKit for the subscription status across all known product IDs,
    /// updates the persisted status, and returns the result.
    @discardableResult
    private func refreshSubscriptionStateFromStoreKit() async -> SubscriptionStatus {
        let productIdentifiers = Set(iaps.map(\.productID))
        let status = await entitlementResolver.resolveStatus(for: productIdentifiers)
        updateSubscriptionState(status)
        return status
    }

    /// Fetches the latest Adapty profile and updates the subscription state.
    ///
    /// When called in StoreKit mode the `storeKitStatus` is passed through so the
    /// merger logic can produce the correct combined status.
    private func refreshSubscriptionStateFromAdapty(storeKitStatus: SubscriptionStatus? = nil) async {
        do {
            let profile = try await adaptyService.profile()
            updateSubscriptionState(from: profile, storeKitStatus: storeKitStatus)
        } catch {
            Log.printLog(l: .error, str: "Failed to verify subscription: \(error.localizedDescription)")
        }
    }

    // MARK: - Private – StoreKit purchase flow

    /// Calls `AppStore.sync()` to reconcile the local receipt with Apple's servers
    /// before a restore operation. Errors are logged and emitted as analytics events
    /// but do not block the restore flow.
    private func syncStoreKitPurchasesForRestore() async {
        do {
            try await storeKitPurchaser.syncWithAppStore()
        } catch {
            let metadata = AnalyticsErrorMetadata(error: error)
            if let logEvent {
                PaywallEventLogger.restoreFailed(
                    reason: .storekitSyncFailed,
                    source: .storeKit,
                    errorDomain: metadata.errorDomain,
                    errorCode: metadata.errorCode,
                    log: logEvent
                )
            }
            Log.printLog(l: .error, str: "Failed to sync StoreKit purchases: \(error.localizedDescription)")
        }
    }

    // MARK: - Private – transaction handling

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
            try await adaptyService.reportTransaction(transaction, variationId: pendingVariationId)
            return true
        } catch {
            Log.printLog(l: .error, str: "Failed to report StoreKit transaction to Adapty: \(error.localizedDescription)")
            return false
        }
    }

    /// Emits the canonical purchase outcome events for a StoreKit purchase.
    private func logStoreKitOutcome(
        _ outcome: StoreKitPurchaseOutcome,
        context: PaywallCheckoutContext,
        log: (EventProtocol) -> Void
    ) {
        switch outcome {
        case .success:
            PaywallEventLogger.purchaseSucceeded(context, log: log)
        case .cancelled:
            PaywallEventLogger.purchaseCancelled(context, log: log)
        case .failed(let errorDomain, let errorCode, let description):
            PaywallEventLogger.purchaseFailed(
                context,
                reason: errorDomain == NSURLErrorDomain ? .networkError : .paymentInvalid,
                errorDomain: errorDomain,
                errorCode: errorCode,
                description: description,
                log: log
            )
        }
    }

    // MARK: - Private – purchase event helpers

    /// Handles the user cancelling an Adapty purchase by logging the appropriate
    /// analytics events and forwarding `.cancel` to the completion handler.
    private func handlePurchaseCancelled(
        checkoutContext: PaywallCheckoutContext,
        completion: @escaping (PurchaseResult) -> Void
    ) {
        if let logEvent {
            PaywallEventLogger.purchaseCancelled(checkoutContext, log: logEvent)
        }
        completion(.cancel)
    }

    /// Handles a non-cancellation failure from an Adapty purchase.
    ///
    /// Adapty maps payment cancellations to an error with code
    /// `paymentCancelled`, so this method delegates to ``handlePurchaseCancelled``
    /// when that specific code is detected, avoiding duplicate event logging.
    private func handlePurchaseFailure(
        error: AdaptyError,
        checkoutContext: PaywallCheckoutContext,
        completion: @escaping (PurchaseResult) -> Void
    ) {
        if error.errorCode == AdaptyError.ErrorCode.paymentCancelled.rawValue {
            handlePurchaseCancelled(
                checkoutContext: checkoutContext,
                completion: completion
            )
        } else {
            let metadata = PaywallFailureMetadata(error: error)
            if let logEvent {
                PaywallEventLogger.purchaseFailed(
                    checkoutContext,
                    adaptyError: error,
                    reason: metadata.reason,
                    log: logEvent
                )
            }
            completion(.fail)
        }
    }
}
