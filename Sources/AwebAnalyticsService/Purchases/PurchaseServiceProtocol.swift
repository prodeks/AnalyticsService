import Combine
import StoreKit
import Adapty

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
    ///   - presentationID: Correlates checkout events with a single paywall presentation.
    ///   - variationId: Adapty A/B variation identifier for the originating paywall.
    ///   - completion: Called on the main thread with the purchase outcome.
    func purchaseAdaptyProduct(
        _ product: AdaptyPaywallProduct,
        paywallID: String,
        presentationID: String?,
        variationId: String?,
        _ completion: @escaping (PurchaseResult) -> Void
    )

    /// Initiates a purchase through StoreKit.
    ///
    /// - Parameters:
    ///   - product: The StoreKit `Product` to purchase.
    ///   - completion: Called on the main thread with the purchase outcome.
    func purchaseProduct(
        _ product: StoreKit.Product,
        _ completion: @escaping (PurchaseResult) -> Void
    )

    /// Initiates a StoreKit purchase from a paywall, logging checkout analytics.
    ///
    /// - Parameters:
    ///   - product: The StoreKit `Product` to purchase.
    ///   - paywallID: Identifier of the originating paywall.
    ///   - placement: The placement from which the purchase was initiated.
    ///   - presentationID: Correlates checkout events with a single paywall presentation.
    ///   - completion: Called on the main thread with the purchase outcome.
    func purchaseProduct(
        _ product: StoreKit.Product,
        paywallID: String,
        placement: String,
        presentationID: String?,
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
