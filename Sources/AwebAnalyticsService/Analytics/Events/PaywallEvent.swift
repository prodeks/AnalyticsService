import Foundation

// MARK: - Base

/// Abstract base class for all paywall-related analytics events.
///
/// Subclasses override `name` to provide a stable event name while inheriting
/// the common `paywallID` parameter. Direct instantiation of this class logs a
/// no-op event (empty `name`) and should be avoided — always use a concrete subclass.
///
/// The class hierarchy is used instead of a protocol/struct approach so that
/// `AnalyticsService.log(e:)` can perform a single `is PaywallEvent` check to
/// identify paywall events when needed without switching over every concrete type.
public class PaywallEvent: EventProtocol {

    public var name: String { "" }

    public var params: [String: Any] { [:] }

    /// The identifier of the paywall that triggered this event.
    ///
    /// Corresponds to the placement or remote-config key used to fetch the paywall.
    /// Included in every concrete subclass's `params` via the event name or as an
    /// explicit parameter.
    let paywallID: String

    public init(paywallID: String) {
        self.paywallID = paywallID
    }
}

// MARK: - Visibility events

/// Logged when a paywall screen becomes visible to the user.
///
/// The event name embeds the `paywallID` so each paywall's open rate can be tracked
/// independently without adding a parameter filter in dashboards.
///
/// Event name: `PaywallOpenEvent_<paywallID>`
public class PaywallOpenEvent: PaywallEvent {
    public override var name: String {
        "PaywallOpenEvent_\(paywallID)"
    }
}

/// Logged when the user dismisses a paywall without completing a purchase.
///
/// Pair with `PaywallOpenEvent` to compute the paywall's dismiss rate.
///
/// Event name: `PaywallClosedEvent_<paywallID>`
public class PaywallClosedEvent: PaywallEvent {
    public override var name: String {
        "PaywallClosedEvent_\(paywallID)"
    }
}

// MARK: - Checkout lifecycle events

/// Logged the moment the user taps a purchase button on a paywall, before the
/// payment sheet is presented.
///
/// Fires regardless of whether the subsequent purchase succeeds, is cancelled, or
/// fails. Use together with `PaywallCheckoutCancelledEvent` and `PurchaseFailedEvent`
/// to compute checkout conversion rates.
///
/// Event name: `paywall_checkout_initiated`
public class PaywallCheckoutStartedEvent: PaywallEvent {
    public override var name: String {
        "paywall_checkout_initiated"
    }
}

/// Logged when the user cancels out of the payment sheet after tapping the purchase
/// button (i.e. after `PaywallCheckoutStartedEvent` but before a purchase outcome).
///
/// Event name: `paywall_checkout_cancelled`
public class PaywallCheckoutCancelledEvent: PaywallEvent {
    public override var name: String {
        "paywall_checkout_cancelled"
    }
}

// MARK: - Failure events

/// Logged when an in-app purchase attempt ends in a non-cancellation failure.
///
/// Includes enough diagnostic context (`reason`, `errorDomain`, `errorCode`) to
/// triage issues without requiring a crash report.
///
/// Event name: `purchaseFailed`
public struct PurchaseFailedEvent: EventProtocol {

    public var name: String { "purchaseFailed" }

    /// Short failure category key used for dashboard grouping.
    ///
    /// Known values: `"cancelled"`, `"network_error"`, `"payment_invalid"`.
    let reason: String

    /// The product identifier that was being purchased when the failure occurred.
    let productID: String

    /// The placement from which the purchase was initiated.
    let placement: String

    /// The `NSError.domain` of the underlying error.
    let errorDomain: String

    /// The numeric error code from the underlying `NSError`.
    let errorCode: Int

    public var params: [String: Any] {
        [
            "reason": reason,
            "productID": productID,
            "placement": placement,
            "errorDomain": errorDomain,
            "errorCode": errorCode
        ]
    }

    public init(
        reason: String,
        productID: String,
        placement: String,
        errorDomain: String,
        errorCode: Int
    ) {
        self.reason = reason
        self.productID = productID
        self.placement = placement
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

/// Logged when `Adapty.restorePurchases()` or `AppStore.sync()` fails.
///
/// Event name: `restoreFailed`
public struct RestoreFailedEvent: EventProtocol {

    public var name: String { "restoreFailed" }

    /// Short failure category key (`"cancelled"`, `"network_error"`,
    /// `"payment_invalid"`, or `"storekit_sync_failed"`).
    let reason: String

    /// The `NSError.domain` of the underlying error.
    let errorDomain: String

    /// The numeric error code from the underlying `NSError`.
    let errorCode: Int

    public var params: [String: Any] {
        [
            "reason": reason,
            "errorDomain": errorDomain,
            "errorCode": errorCode
        ]
    }

    public init(
        reason: String,
        errorDomain: String,
        errorCode: Int
    ) {
        self.reason = reason
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

/// Logged when loading product prices from StoreKit fails.
///
/// Typically caused by network issues or an invalid product configuration in App Store
/// Connect. Dashboards can use `errorCode` to detect App Store outages.
///
/// Event name: `pricesFailed`
public struct PricesFailedEvent: EventProtocol {

    public var name: String { "pricesFailed" }

    /// The `NSError.domain` of the underlying StoreKit error.
    let errorDomain: String

    /// The numeric error code from the underlying StoreKit error.
    let errorCode: Int

    public var params: [String: Any] {
        [
            "errorDomain": errorDomain,
            "errorCode": errorCode
        ]
    }

    public init(errorDomain: String, errorCode: Int) {
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

/// Logged when a paywall cannot be presented for a given placement.
///
/// Covers both Adapty-side failures (e.g. remote config not loaded) and
/// `DirectStoreKitPaywallService` failures (e.g. products not fetched yet).
/// The `placement` parameter identifies which entry point failed.
///
/// Event name: `paywallFailed`
public struct PaywallFailedEvent: EventProtocol {

    public var name: String { "paywallFailed" }

    /// The placement identifier for which the paywall could not be shown.
    let placement: String

    /// The `NSError.domain` of the underlying error.
    let errorDomain: String

    /// The numeric error code from the underlying error.
    let errorCode: Int

    public var params: [String: Any] {
        [
            "placement": placement,
            "errorDomain": errorDomain,
            "errorCode": errorCode
        ]
    }

    public init(placement: String, errorDomain: String, errorCode: Int) {
        self.placement = placement
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

// MARK: - Analytics error helpers

/// Lightweight wrapper that extracts `domain` and `code` from any `Error` for use in
/// analytics event payloads.
///
/// Avoids scattering `(error as NSError).domain` / `.code` boilerplate across the
/// codebase. For Adapty-specific errors prefer `PaywallFailureMetadata` which also
/// normalises the `reason` string.
struct AnalyticsErrorMetadata {

    /// The `NSError.domain` of the wrapped error.
    let errorDomain: String

    /// The `NSError.code` of the wrapped error.
    let errorCode: Int

    init(error: Error) {
        let nsError = error as NSError
        self.errorDomain = nsError.domain
        self.errorCode = nsError.code
    }

    init(errorDomain: String, errorCode: Int) {
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

/// Namespace for well-known `AnalyticsErrorMetadata` constants used when paywall
/// presentation fails for reasons unrelated to a real underlying system error.
///
/// All constants share the domain `"AwebAnalyticsService.Paywall"` and use negative
/// error codes to avoid collisions with StoreKit / Adapty error codes.
///
/// | Code | Meaning |
/// |---|---|
/// | -1 | Product identifiers are missing from the IAP configuration |
/// | -2 | Product identifiers are present but don't match any StoreKit product |
/// | -101 | Adapty returned no paywall data for the requested placement |
/// | -102 | A custom view was requested but the `uiFactory` returned `nil` |
/// | -103 | `getPaywall(_:)` was called for a placement that has not been configured |
/// | -104 | A `PaywallIdentifier` could not be resolved for the placement |
/// | -105 | `getPaywall(_:)` was called before `fetchProducts()` completed |
enum PaywallAnalyticsError {

    static let domain = "AwebAnalyticsService.Paywall"

    static let missingProductIdentifiers   = AnalyticsErrorMetadata(errorDomain: domain, errorCode: -1)
    static let invalidProductIdentifiers   = AnalyticsErrorMetadata(errorDomain: domain, errorCode: -2)
    static let missingPaywallData          = AnalyticsErrorMetadata(errorDomain: domain, errorCode: -101)
    static let customViewUnavailable       = AnalyticsErrorMetadata(errorDomain: domain, errorCode: -102)
    static let unconfiguredPlacement       = AnalyticsErrorMetadata(errorDomain: domain, errorCode: -103)
    static let missingViewIdentifier       = AnalyticsErrorMetadata(errorDomain: domain, errorCode: -104)
    static let productsNotLoaded           = AnalyticsErrorMetadata(errorDomain: domain, errorCode: -105)
}

// MARK: - Fetch / lifecycle events

/// Logged when the SDK fails to fetch paywall configuration or products from the
/// network, providing enough context to diagnose the failing placement.
///
/// Event name: `paywall_fetch_error`
public struct PaywallFetchErrorEvent: EventProtocol {

    public var name: String { "paywall_fetch_error" }

    /// The placement for which the fetch was attempted.
    let placement: String

    /// Human-readable description of the underlying error.
    let errorDescription: String

    public var params: [String: Any] {
        ["placement": placement, "error": errorDescription]
    }
}

/// Logged once when the app's onboarding flow starts.
///
/// Used as a top-of-funnel anchor event in acquisition and conversion dashboards.
///
/// Event name: `Onboarding_Started`
public struct OnboardingStartedEvent: EventProtocol {

    public var name: String { "Onboarding_Started" }

    public var params: [String: Any] { [:] }

    public init() {}
}
