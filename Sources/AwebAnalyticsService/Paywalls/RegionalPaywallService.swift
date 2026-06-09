import Foundation

/// A paywall service that transparently routes to different backends depending on the
/// user's region.
///
/// Chinese App Store users cannot use Adapty paywalls due to regional restrictions, so
/// they are served via a direct StoreKit integration (`DirectStoreKitPaywallService`).
/// All other regions continue to use Adapty (`PaywallService`).
///
/// Configuration is driven by a single call to ``configure(isRunningInChina:)`` which
/// selects the active backend and adjusts how entitlements are verified.
///
/// Forwarded properties (`placements`, `uiFactory`, `viewIdentifiersByPlacement`) are
/// propagated to both underlying services so they stay in sync regardless of which one
/// is currently active.
@MainActor
final class RegionalPaywallService: PaywallServiceProtocol {

    /// The set of placement identifiers managed by this service.
    ///
    /// Propagated to both underlying services on every change so either backend is
    /// ready to serve any placement without requiring re-assignment after a region
    /// switch.
    var placements = Set<String>() {
        didSet {
            adaptyPaywallService.placements = placements
            directStoreKitPaywallService.placements = placements
        }
    }

    /// Factory closure that vends a custom `PaywallViewProtocol` for a given
    /// `PaywallIdentifier`, or `nil` to use the default presentation.
    ///
    /// Forwarded to both services so the same factory is available regardless of the
    /// active backend.
    var uiFactory: ((PaywallIdentifier) -> PaywallViewProtocol?)? {
        didSet {
            adaptyPaywallService.uiFactory = uiFactory
            directStoreKitPaywallService.uiFactory = uiFactory
        }
    }

    /// Mapping from placement strings to the `PaywallIdentifier` that should be
    /// presented for each placement.
    ///
    /// Only forwarded to `DirectStoreKitPaywallService` because the Adapty service
    /// resolves view identifiers through its own remote configuration.
    var viewIdentifiersByPlacement = [String: PaywallIdentifier]() {
        didSet {
            directStoreKitPaywallService.viewIdentifiersByPlacement = viewIdentifiersByPlacement
        }
    }

    // MARK: - Private types

    /// Discriminates which paywall backend is currently in use.
    private enum ActiveService {
        /// Adapty-managed paywalls — used outside of China.
        case adapty
        /// Direct StoreKit paywalls — used inside China where Adapty is unavailable.
        case directStoreKit
    }

    // MARK: - Private properties

    private let adaptyPaywallService: PaywallService
    private let directStoreKitPaywallService: DirectStoreKitPaywallService
    private let purchaseService: PurchaseService

    /// The currently active backend. Defaults to `.adapty` until
    /// ``configure(isRunningInChina:)`` is called.
    private var activeService: ActiveService = .adapty

    // MARK: - Init

    init(purchaseService: PurchaseService, analyticsService: AnalyticsService) {
        self.purchaseService = purchaseService
        self.adaptyPaywallService = PaywallService(
            purchaseService: purchaseService,
            analyticsService: analyticsService
        )
        self.directStoreKitPaywallService = DirectStoreKitPaywallService(
            purchaseService: purchaseService,
            logEvent: analyticsService.log(e:)
        )
    }

    // MARK: - PaywallServiceProtocol

    /// Selects the appropriate backend and configures entitlement verification strategy.
    ///
    /// - Parameter isRunningInChina: Pass `true` when the app determines the user is in
    ///   the Chinese App Store. This switches the active service to
    ///   `DirectStoreKitPaywallService` and instructs `PurchaseService` to derive access
    ///   from StoreKit entitlements rather than Adapty profile data.
    func configure(isRunningInChina: Bool) {
        activeService = isRunningInChina ? .directStoreKit : .adapty
        purchaseService.usesStoreKitEntitlementsForAccess = isRunningInChina
    }

    /// Returns the paywall controller for the given placement, using whichever backend
    /// is currently active.
    ///
    /// - Parameter placement: The placement descriptor identifying which paywall to show.
    /// - Returns: A `PaywallControllerProtocol` ready for presentation, or `nil` if no
    ///   paywall is configured for the placement.
    func getPaywall(_ placement: PaywallPlacementProtocol) -> PaywallControllerProtocol? {
        switch activeService {
        case .adapty:
            return adaptyPaywallService.getPaywall(placement)
        case .directStoreKit:
            return directStoreKitPaywallService.getPaywall(placement)
        }
    }

    /// Registers a local JSON file as a fallback paywall configuration for Adapty.
    ///
    /// Only relevant for the Adapty backend; has no effect when running in China.
    ///
    /// - Parameter url: URL to the bundled fallback paywalls JSON file.
    func setFallbackPaywalls(url: URL) {
        adaptyPaywallService.setFallbackPaywalls(url: url)
    }

    /// Pre-fetches paywalls and their associated products from the active backend.
    ///
    /// Call this early in the app lifecycle (e.g. after launch) to ensure paywall data
    /// is available before the user reaches a purchase point.
    func fetchPaywallsAndProducts() async {
        switch activeService {
        case .adapty:
            await adaptyPaywallService.fetchPaywallsAndProducts()
        case .directStoreKit:
            await directStoreKitPaywallService.fetchProducts()
        }
    }
}
