import UIKit
import StoreKit

/// The single entry point for analytics, purchases, paywalls, and remote configuration.
///
/// `PurchasesAndAnalytics` wires the package's services together and runs a coordinated
/// cold-start sequence: detect the user's region, configure the paywall backend,
/// sign in to Firebase, activate Adapty, and prefetch paywalls, subscription state,
/// and remote config in parallel.
///
/// ## Usage
///
/// 1. Assign API keys on ``Keys`` before any service is touched (typically in
///    `application(_:didFinishLaunchingWithOptions:)`).
/// 2. Optionally assign ``viewIdentifiersByPlacement`` for direct StoreKit paywalls.
/// 3. Set ``dataFetchComplete`` **before** calling into analytics setup so the host
///    app is notified when startup work finishes.
/// 4. Forward app lifecycle methods to ``analytics`` (see `AnalyticsServiceProtocol`).
///
/// ```swift
/// PurchasesAndAnalytics.Keys.subscriptionServiceKey = "…"
/// PurchasesAndAnalytics.shared.dataFetchComplete = { options in
///     // Navigate past splash / unlock UI
/// }
/// PurchasesAndAnalytics.shared.analytics.didFinishLaunchingWithOptions(
///     application: application,
///     options: launchOptions
/// )
/// ```
///
/// ## Service graph
///
/// ```
/// PurchasesAndAnalytics
/// ├── analytics  → AnalyticsService
/// ├── purchases  → PurchaseService  (logEvent → analytics.log)
/// ├── paywalls   → RegionalPaywallService (Adapty vs Direct StoreKit)
/// └── remoteConfig → RemoteConfigService.shared
/// ```
///
/// Access services through the public `lazy` properties so concrete types stay
/// internal while callers depend only on protocols.
@MainActor public class PurchasesAndAnalytics {

    // MARK: - Public service accessors

    /// Analytics and attribution (Firebase, Adapty, Adjust, AppsFlyer, Mixpanel, etc.).
    public lazy var analytics: AnalyticsServiceProtocol = _analytics

    /// In-app purchases and subscription state.
    public lazy var purchases: PurchaseServiceProtocol = _purchases

    /// Paywall presentation; routes to Adapty or direct StoreKit based on region.
    public lazy var paywalls: PaywallServiceProtocol = _paywalls

    /// Firebase Remote Config wrapper used during startup prefetch.
    public lazy var remoteConfig: RemoteConfigServiceProtocol = _remoteConfig

    // MARK: - Internal service instances

    /// Concrete analytics implementation. Shared by paywalls and the `log` bridge.
    lazy var _analytics = AnalyticsService()

    /// Concrete purchase service. Receives analytics events via `logEvent`.
    lazy var _purchases = PurchaseService()

    /// Region-aware paywall facade backed by Adapty or `DirectStoreKitPaywallService`.
    lazy var _paywalls = AdaptyPaywallService(purchaseService: _purchases, analyticsService: _analytics)

    lazy var _remoteConfig = RemoteConfigService.shared

    // MARK: - Paywall configuration

//    /// Maps placement identifiers to the `PaywallIdentifier` used by the direct
//    /// StoreKit paywall path (China / Ukraine).
//    ///
//    /// Assign before or after accessing `paywalls`; changes are forwarded to
//    /// `RegionalPaywallService` via `didSet`. Ignored by the Adapty backend, which
//    /// resolves view identifiers from remote configuration.
//    public var viewIdentifiersByPlacement: [String: PaywallIdentifier] = [:] {
//        didSet {
//            _paywalls.viewIdentifiersByPlacement = viewIdentifiersByPlacement
//        }
//    }

    // MARK: - Startup callback

    /// Called on the main actor after the post-launch prefetch bundle completes.
    ///
    /// Set this property on ``shared`` **before** analytics setup runs (i.e. before
    /// `analytics.didFinishLaunchingWithOptions` / `setupAnalyticsIfNeeded` triggers
    /// ``AnalyticsService/analyticsStarted``). The closure receives the same launch
    /// options passed into analytics setup.
    ///
    /// Prefetch work (run in parallel inside `analyticsStarted`):
    /// - `paywalls.fetchPaywallsAndProducts()`
    /// - `purchases.verifySubscriptionIfNeeded()`
    /// - `remoteConfig.fetch()`
    public var dataFetchComplete: (([UIApplication.LaunchOptionsKey: Any]?) -> Void)?

    // MARK: - Singleton

    /// Shared instance. Initialisation wires purchase logging and registers the
    /// analytics startup handler; no network I/O occurs until analytics setup is invoked.
    public static let shared = PurchasesAndAnalytics()

    // MARK: - Init

    private init() {
        // Forward purchase-related analytics events without a hard dependency from
        // PurchaseService on AnalyticsService.
        _purchases.logEvent = self.log

        // Runs once when the host app calls setupAnalyticsIfNeeded / didFinishLaunching.
        _analytics.analyticsStarted = { options in
            Task {
                let isRunningInChina = await self.isRunningInChina()
                self._analytics.isRunningInChina = isRunningInChina
                await self._analytics.firebaseSignIn(options)

                // Prefetch in parallel to minimise time-to-interactive after splash.
                async let paywallsTask: Void = self._paywalls.fetchPaywallsAndProducts()
                async let subscriptionTask: Void = self._purchases.verifySubscriptionIfNeeded()
                async let remoteConfigTask: Void = self._remoteConfig.fetch()

                _ = await (paywallsTask, subscriptionTask, remoteConfigTask)

                await MainActor.run {
                    self.dataFetchComplete?(options)
                }
            }
        }
    }

    // MARK: - Region detection

    /// Determines whether the app should use the direct StoreKit paywall and
    /// entitlement path instead of Adapty-managed purchases.
    ///
    /// Returns `true` when either signal matches a supported restricted region
    /// Storefront is preferred because it reflects the App Store the user is signed
    /// into. Locale is a fallback for environments without a storefront (e.g. Simulator).
    ///
    /// When `true`, ``RegionalPaywallService/configure(isRunningInChina:)`` selects
    /// `DirectStoreKitPaywallService` and sets `PurchaseService.usesStoreKitEntitlementsForAccess`.
    private func isRunningInChina() async -> Bool {
        let storefront = await Storefront.current?.countryCode
        let locale = Locale.current.region?.identifier

        let result = storefront == "CHN" || locale == "CN"
        return result
    }

    // MARK: - Event bridge

    /// Forwards events from `PurchaseService` to the analytics layer.
    ///
    /// Uses the public `analytics` accessor so callers that replace `analytics` with a
    /// test double still route purchase events correctly.
    func log(_ e: EventProtocol) {
        analytics.log(e: e)
    }

    /// Logs the onboarding funnel anchor event. Call from the host app when onboarding starts.
    public func logOnboardingStarted() {
        analytics.log(e: OnboardingStartedEvent())
    }
}
