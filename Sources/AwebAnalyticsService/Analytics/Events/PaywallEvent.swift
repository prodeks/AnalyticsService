import Foundation
import Adapty

// MARK: - Failure reason

/// Normalised failure categories for paywall and purchase analytics.
public enum PaywallFailureReason: String {
    case cancelled = "cancelled"
    case networkError = "network_error"
    case paymentInvalid = "payment_invalid"
    case storekitSyncFailed = "storekit_sync_failed"
}

public enum PaywallSource {
    case adapty
    case storeKit

    var eventPrefix: String {
        switch self {
        case .adapty: return "adapty_"
        case .storeKit: return "storekit_"
        }
    }
}

// MARK: - Presentation context

/// Correlates open, checkout, outcome, and close events for a single paywall presentation.
struct PaywallPresentationContext {
    let presentationID: String
    let paywallID: String
    let placement: String
    let variationId: String?
    let source: PaywallSource

    init(paywallID: String, placement: String, variationId: String? = nil, source: PaywallSource) {
        self.presentationID = UUID().uuidString
        self.paywallID = paywallID
        self.placement = placement
        self.variationId = variationId
        self.source = source
    }
}

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

    public var params: [String: Any] {
        var result: [String: Any] = ["paywallID": paywallID]
        if let placement {
            result["placement"] = placement
        }
        if let productID {
            result["productID"] = productID
        }
        if let price {
            result["price"] = price
        }
        if let currency {
            result["currency"] = currency
        }
        if let variationId {
            result["variationId"] = variationId
        }
        if let presentationID {
            result["presentationID"] = presentationID
        }
        return result
    }

    /// The identifier of the paywall that triggered this event.
    ///
    /// Corresponds to the placement or remote-config key used to fetch the paywall.
    let paywallID: String

    let placement: String?
    let productID: String?
    let price: Float?
    let currency: String?
    let variationId: String?
    let presentationID: String?
    let source: PaywallSource

    public init(
        paywallID: String,
        placement: String? = nil,
        productID: String? = nil,
        price: Float? = nil,
        currency: String? = nil,
        variationId: String? = nil,
        presentationID: String? = nil,
        source: PaywallSource
    ) {
        self.paywallID = paywallID
        self.placement = placement
        self.productID = productID
        self.price = price
        self.currency = currency
        self.variationId = variationId
        self.presentationID = presentationID
        self.source = source
    }

    convenience init(context: PaywallPresentationContext) {
        self.init(
            paywallID: context.paywallID,
            placement: context.placement,
            variationId: context.variationId,
            presentationID: context.presentationID,
            source: context.source
        )
    }

    convenience init(context: PaywallPresentationContext, product: AdaptyProductContext) {
        self.init(
            paywallID: context.paywallID,
            placement: context.placement,
            productID: product.productID,
            price: product.price,
            currency: product.currency,
            variationId: context.variationId,
            presentationID: context.presentationID,
            source: context.source
        )
    }
}

/// Product-level economics extracted from an Adapty paywall product.
struct AdaptyProductContext {
    let productID: String
    let price: Float
    let currency: String

    init(product: any AdaptyPaywallProduct) {
        self.productID = product.vendorProductId
        self.price = Float(truncating: product.price as NSNumber)
        self.currency = product.priceLocale.currency?.identifier ?? product.currencyCode ?? "USD"
    }
}

/// Product and presentation data shared by every checkout analytics event.
struct PaywallCheckoutContext {
    let paywallID: String
    let placement: String
    let productID: String
    let price: Float
    let currency: String
    let variationId: String?
    let presentationID: String?
    let source: PaywallSource

    init(
        paywallID: String,
        placement: String,
        productID: String,
        price: Float,
        currency: String,
        variationId: String? = nil,
        presentationID: String? = nil,
        source: PaywallSource
    ) {
        self.paywallID = paywallID
        self.placement = placement
        self.productID = productID
        self.price = price
        self.currency = currency
        self.variationId = variationId
        self.presentationID = presentationID
        self.source = source
    }

    init(
        paywallID: String,
        placement: String,
        product: AdaptyProductContext,
        variationId: String? = nil,
        presentationID: String? = nil,
        source: PaywallSource
    ) {
        self.init(
            paywallID: paywallID,
            placement: placement,
            productID: product.productID,
            price: product.price,
            currency: product.currency,
            variationId: variationId,
            presentationID: presentationID,
            source: source
        )
    }
}

/// Legacy button-tap event promoted to all checkout paths for consistent funnels.
struct PaywallStartButtonTapEvent: EventProtocol {
    let source: PaywallSource

    var name: String { "\(source.eventPrefix)Paywall_Start_Button_tap" }
    var params: [String: Any] { [:] }
}

/// Emits the canonical paywall purchase funnel event set for every backend.
enum PaywallEventLogger {

    static func checkoutStarted(_ context: PaywallCheckoutContext, log: (EventProtocol) -> Void) {
        log(
            PaywallCheckoutStartedEvent(
                paywallID: context.paywallID,
                placement: context.placement,
                productID: context.productID,
                price: context.price,
                currency: context.currency,
                variationId: context.variationId,
                presentationID: context.presentationID,
                source: context.source
            )
        )
        log(PaywallStartButtonTapEvent(source: context.source))
    }

    static func purchaseSucceeded(_ context: PaywallCheckoutContext, log: (EventProtocol) -> Void) {
        log(
            PurchaseEvent.success(
                source: context.source,
                iap: (
                    context.productID,
                    context.price,
                    context.currency
                )
            )
        )
    }

    static func purchaseCancelled(_ context: PaywallCheckoutContext, log: (EventProtocol) -> Void) {
        let metadata = PaywallFailureMetadata.cancelled
        log(
            PurchaseEvent.cancel(
                source: context.source,
                iap: (
                    context.productID,
                    context.price,
                    context.currency
                )
            )
        )
        log(
            PaywallCheckoutCancelledEvent(
                paywallID: context.paywallID,
                placement: context.placement,
                productID: context.productID,
                price: context.price,
                currency: context.currency,
                variationId: context.variationId,
                presentationID: context.presentationID,
                source: context.source
            )
        )
        log(
            PurchaseFailedEvent(
                reason: metadata.reason,
                source: context.source,
                productID: context.productID,
                placement: context.placement,
                errorDomain: metadata.errorDomain,
                errorCode: metadata.errorCode,
                price: context.price,
                currency: context.currency,
                paywallID: context.paywallID,
                presentationID: context.presentationID,
                variationId: context.variationId
            )
        )
    }

    static func purchaseFailed(
        _ context: PaywallCheckoutContext,
        reason: PaywallFailureReason,
        errorDomain: String,
        errorCode: Int,
        description: String,
        value: String? = nil,
        log: (EventProtocol) -> Void
    ) {
        let payload = PurchaseFailurePayload(
            productID: context.productID,
            errorDomain: errorDomain,
            errorCode: errorCode,
            description: description,
            value: value
        )
        log(PurchaseEvent.fail(source: context.source, payload))
        log(
            PurchaseFailedEvent(
                reason: reason,
                source: context.source,
                productID: context.productID,
                placement: context.placement,
                errorDomain: errorDomain,
                errorCode: errorCode,
                price: context.price,
                currency: context.currency,
                paywallID: context.paywallID,
                presentationID: context.presentationID,
                variationId: context.variationId
            )
        )
    }

    static func purchaseFailed(
        _ context: PaywallCheckoutContext,
        adaptyError error: AdaptyError,
        reason: PaywallFailureReason,
        log: (EventProtocol) -> Void
    ) {
        let payload = PurchaseFailurePayload(adaptyError: error, productID: context.productID)
        log(PurchaseEvent.fail(source: context.source, payload))
        log(
            PurchaseFailedEvent(
                reason: reason,
                source: context.source,
                productID: context.productID,
                placement: context.placement,
                errorDomain: payload.errorDomain,
                errorCode: payload.errorCode,
                price: context.price,
                currency: context.currency,
                paywallID: context.paywallID,
                presentationID: context.presentationID,
                variationId: context.variationId
            )
        )
    }

    static func restoreSucceeded(source: PaywallSource, log: (EventProtocol) -> Void) {
        log(PurchaseEvent.restore(source: source))
    }

    static func restoreFailed(
        reason: PaywallFailureReason,
        source: PaywallSource,
        errorDomain: String,
        errorCode: Int,
        log: (EventProtocol) -> Void
    ) {
        log(
            RestoreFailedEvent(
                reason: reason,
                source: source,
                errorDomain: errorDomain,
                errorCode: errorCode
            )
        )
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
        "\(source.eventPrefix)PaywallOpenEvent_\(paywallID)"
    }
}

/// Logged when the user dismisses a paywall without completing a purchase.
///
/// Pair with `PaywallOpenEvent` to compute the paywall's dismiss rate.
///
/// Event name: `PaywallClosedEvent_<paywallID>`
public class PaywallClosedEvent: PaywallEvent {

    let purchased: Bool

    public override var params: [String: Any] {
        var result = super.params
        result["purchased"] = purchased
        return result
    }

    public init(
        paywallID: String,
        purchased: Bool,
        placement: String? = nil,
        variationId: String? = nil,
        presentationID: String? = nil,
        source: PaywallSource
    ) {
        self.purchased = purchased
        super.init(
            paywallID: paywallID,
            placement: placement,
            variationId: variationId,
            presentationID: presentationID,
            source: source
        )
    }

    convenience init(context: PaywallPresentationContext, purchased: Bool) {
        self.init(
            paywallID: context.paywallID,
            purchased: purchased,
            placement: context.placement,
            variationId: context.variationId,
            presentationID: context.presentationID,
            source: context.source
        )
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
        "\(source.eventPrefix)paywall_checkout_initiated"
    }
}

/// Logged when the user cancels out of the payment sheet after tapping the purchase
/// button (i.e. after `PaywallCheckoutStartedEvent` but before a purchase outcome).
///
/// Event name: `paywall_checkout_cancelled`
public class PaywallCheckoutCancelledEvent: PaywallEvent {
    public override var name: String {
        "\(source.eventPrefix)paywall_checkout_cancelled"
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

    public var name: String { "\(source.eventPrefix)purchaseFailed" }

    /// Short failure category key used for dashboard grouping.
    let reason: String
    let source: PaywallSource

    /// The product identifier that was being purchased when the failure occurred.
    let productID: String

    /// The placement from which the purchase was initiated.
    let placement: String

    /// The `NSError.domain` of the underlying error.
    let errorDomain: String

    /// The numeric error code from the underlying `NSError`.
    let errorCode: Int

    let price: Float?
    let currency: String?
    let paywallID: String?
    let presentationID: String?
    let variationId: String?

    public var params: [String: Any] {
        var result: [String: Any] = [
            "reason": reason,
            "productID": productID,
            "placement": placement,
            "errorDomain": errorDomain,
            "errorCode": errorCode
        ]
        if let price {
            result["price"] = price
        }
        if let currency {
            result["currency"] = currency
        }
        if let paywallID {
            result["paywallID"] = paywallID
        }
        if let presentationID {
            result["presentationID"] = presentationID
        }
        if let variationId {
            result["variationId"] = variationId
        }
        return result
    }

    public init(
        reason: PaywallFailureReason,
        source: PaywallSource,
        productID: String,
        placement: String,
        errorDomain: String,
        errorCode: Int,
        price: Float? = nil,
        currency: String? = nil,
        paywallID: String? = nil,
        presentationID: String? = nil,
        variationId: String? = nil
    ) {
        self.reason = reason.rawValue
        self.source = source
        self.productID = productID
        self.placement = placement
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.price = price
        self.currency = currency
        self.paywallID = paywallID
        self.presentationID = presentationID
        self.variationId = variationId
    }

    public init(
        reason: String,
        source: PaywallSource,
        productID: String,
        placement: String,
        errorDomain: String,
        errorCode: Int,
        price: Float? = nil,
        currency: String? = nil,
        paywallID: String? = nil,
        presentationID: String? = nil,
        variationId: String? = nil
    ) {
        self.reason = reason
        self.source = source
        self.productID = productID
        self.placement = placement
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.price = price
        self.currency = currency
        self.paywallID = paywallID
        self.presentationID = presentationID
        self.variationId = variationId
    }
}

/// Logged when `Adapty.restorePurchases()` or `AppStore.sync()` fails.
///
/// Event name: `restoreFailed`
public struct RestoreFailedEvent: EventProtocol {

    public var name: String { "\(source.eventPrefix)restoreFailed" }

    /// Short failure category key (`"cancelled"`, `"network_error"`,
    /// `"payment_invalid"`, or `"storekit_sync_failed"`).
    let reason: String
    let source: PaywallSource

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
        reason: PaywallFailureReason,
        source: PaywallSource,
        errorDomain: String,
        errorCode: Int
    ) {
        self.reason = reason.rawValue
        self.source = source
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }

    public init(
        reason: String,
        source: PaywallSource,
        errorDomain: String,
        errorCode: Int
    ) {
        self.reason = reason
        self.source = source
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

    public var name: String { "\(source.eventPrefix)pricesFailed" }

    /// The `NSError.domain` of the underlying StoreKit error.
    let errorDomain: String
    let source: PaywallSource

    /// The numeric error code from the underlying StoreKit error.
    let errorCode: Int

    /// Product identifiers that failed to load from StoreKit.
    let failedIdentifiers: [String]

    /// Short failure category key used for dashboard grouping.
    let reason: String

    /// Human-readable description of the underlying error.
    let errorDescription: String

    public var params: [String: Any] {
        var result: [String: Any] = [
            "reason": reason,
            "error": errorDescription,
            "errorDomain": errorDomain,
            "errorCode": errorCode
        ]
        if !failedIdentifiers.isEmpty {
            result["failedIdentifiers"] = failedIdentifiers
        }
        return result
    }

    public init(
        source: PaywallSource,
        errorDomain: String,
        errorCode: Int,
        reason: String,
        errorDescription: String,
        failedIdentifiers: [String] = []
    ) {
        self.source = source
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.reason = reason
        self.errorDescription = errorDescription
        self.failedIdentifiers = failedIdentifiers
    }

    init(source: PaywallSource, metadata: AnalyticsErrorMetadata, failedIdentifiers: [String] = []) {
        self.init(
            source: source,
            errorDomain: metadata.errorDomain,
            errorCode: metadata.errorCode,
            reason: metadata.reasonRawValue,
            errorDescription: metadata.humanReadableReason,
            failedIdentifiers: failedIdentifiers
        )
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

    public var name: String { "\(source.eventPrefix)paywallFailed" }

    /// The placement identifier for which the paywall could not be shown.
    let placement: String
    let source: PaywallSource

    /// The `NSError.domain` of the underlying error.
    let errorDomain: String

    /// The numeric error code from the underlying error.
    let errorCode: Int

    /// Short failure category key used for dashboard grouping.
    let reason: String

    /// Human-readable description of the underlying error.
    let errorDescription: String

    public var params: [String: Any] {
        [
            "placement": placement,
            "reason": reason,
            "error": errorDescription,
            "errorDomain": errorDomain,
            "errorCode": errorCode
        ]
    }

    public init(
        source: PaywallSource,
        placement: String,
        errorDomain: String,
        errorCode: Int,
        reason: String,
        errorDescription: String
    ) {
        self.source = source
        self.placement = placement
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.reason = reason
        self.errorDescription = errorDescription
    }

    init(source: PaywallSource, placement: String, metadata: AnalyticsErrorMetadata) {
        self.init(
            source: source,
            placement: placement,
            errorDomain: metadata.errorDomain,
            errorCode: metadata.errorCode,
            reason: metadata.reasonRawValue,
            errorDescription: metadata.humanReadableReason
        )
    }
}

// MARK: - Analytics error helpers

/// Normalised failure categories for non-Adapty analytics errors.
public enum AnalyticsErrorReason: String {
    case missingProductIdentifiers = "missing_product_identifiers"
    case invalidProductIdentifiers = "invalid_product_identifiers"
    case missingPaywallData = "missing_paywall_data"
    case customViewUnavailable = "custom_view_unavailable"
    case unconfiguredPlacement = "unconfigured_placement"
    case missingViewIdentifier = "missing_view_identifier"
    case productsNotLoaded = "products_not_loaded"
    case networkError = "network_error"
    case storeKitError = "storekit_error"
    case unknown = "unknown"

    var humanReadable: String {
        switch self {
        case .missingProductIdentifiers:
            return "Product identifiers are missing from the IAP configuration"
        case .invalidProductIdentifiers:
            return "Product identifiers are present but don't match any StoreKit product"
        case .missingPaywallData:
            return "Adapty returned no paywall data for the requested placement"
        case .customViewUnavailable:
            return "A custom view was requested but the uiFactory returned nil"
        case .unconfiguredPlacement:
            return "getPaywall(_:) was called for a placement that has not been configured"
        case .missingViewIdentifier:
            return "A PaywallIdentifier could not be resolved for the placement"
        case .productsNotLoaded:
            return "getPaywall(_:) was called before fetchProducts() completed"
        case .networkError:
            return "A network error occurred"
        case .storeKitError:
            return "A StoreKit error occurred"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

/// Lightweight wrapper that extracts `domain`, `code`, and a normalised reason from
/// any `Error` for use in analytics event payloads.
///
/// Avoids scattering `(error as NSError).domain` / `.code` boilerplate across the
/// codebase. For Adapty-specific errors prefer `PaywallFailureMetadata` which also
/// normalises the `reason` string.
struct AnalyticsErrorMetadata {

    /// Normalised failure category key used for dashboard grouping.
    let reason: AnalyticsErrorReason

    /// Human-readable description suitable for analytics dashboards.
    let humanReadableReason: String

    /// The `NSError.domain` of the wrapped error.
    let errorDomain: String

    /// The `NSError.code` of the wrapped error.
    let errorCode: Int

    var reasonRawValue: String { reason.rawValue }

    init(reason: AnalyticsErrorReason, humanReadableReason: String? = nil, errorDomain: String, errorCode: Int) {
        self.reason = reason
        self.humanReadableReason = humanReadableReason ?? reason.humanReadable
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }

    init(error: Error) {
        let nsError = error as NSError
        let reason = Self.reason(nsError: nsError)
        self.reason = reason
        self.humanReadableReason = reason == .unknown
            ? error.localizedDescription
            : reason.humanReadable
        self.errorDomain = nsError.domain
        self.errorCode = nsError.code
    }

    init(errorDomain: String, errorCode: Int) {
        let reason = Self.reason(errorDomain: errorDomain, errorCode: errorCode)
        self.init(reason: reason, errorDomain: errorDomain, errorCode: errorCode)
    }

    private static func reason(errorDomain: String, errorCode: Int) -> AnalyticsErrorReason {
        guard errorDomain == PaywallAnalyticsError.domain else {
            return .unknown
        }

        switch errorCode {
        case -1: return .missingProductIdentifiers
        case -2: return .invalidProductIdentifiers
        case -101: return .missingPaywallData
        case -102: return .customViewUnavailable
        case -103: return .unconfiguredPlacement
        case -104: return .missingViewIdentifier
        case -105: return .productsNotLoaded
        default: return .unknown
        }
    }

    private static func reason(nsError: NSError) -> AnalyticsErrorReason {
        if nsError.domain == PaywallAnalyticsError.domain {
            return reason(errorDomain: nsError.domain, errorCode: nsError.code)
        }

        if isNetworkError(nsError) {
            return .networkError
        }

        if nsError.domain == "SKErrorDomain" || nsError.domain.contains("StoreKit") {
            return .storeKitError
        }

        return .unknown
    }

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

    static let missingProductIdentifiers   = AnalyticsErrorMetadata(reason: .missingProductIdentifiers, errorDomain: domain, errorCode: -1)
    static let invalidProductIdentifiers   = AnalyticsErrorMetadata(reason: .invalidProductIdentifiers, errorDomain: domain, errorCode: -2)
    static let missingPaywallData          = AnalyticsErrorMetadata(reason: .missingPaywallData, errorDomain: domain, errorCode: -101)
    static let customViewUnavailable       = AnalyticsErrorMetadata(reason: .customViewUnavailable, errorDomain: domain, errorCode: -102)
    static let unconfiguredPlacement       = AnalyticsErrorMetadata(reason: .unconfiguredPlacement, errorDomain: domain, errorCode: -103)
    static let missingViewIdentifier       = AnalyticsErrorMetadata(reason: .missingViewIdentifier, errorDomain: domain, errorCode: -104)
    static let productsNotLoaded           = AnalyticsErrorMetadata(reason: .productsNotLoaded, errorDomain: domain, errorCode: -105)
}

// MARK: - Fetch / lifecycle events

/// Logged when the SDK fails to fetch paywall configuration or products from the
/// network, providing enough context to diagnose the failing placement.
///
/// Event name: `paywall_fetch_error`
public struct PaywallFetchErrorEvent: EventProtocol {

    public var name: String { "\(source.eventPrefix)paywall_fetch_error" }

    /// The placement for which the fetch was attempted.
    let placement: String
    let source: PaywallSource

    /// Human-readable description of the underlying error.
    let errorDescription: String

    /// The `NSError.domain` of the underlying error.
    let errorDomain: String

    /// The numeric error code from the underlying error.
    let errorCode: Int

    public var params: [String: Any] {
        [
            "placement": placement,
            "error": errorDescription,
            "errorDomain": errorDomain,
            "errorCode": errorCode
        ]
    }

    public init(source: PaywallSource, placement: String, errorDescription: String, errorDomain: String, errorCode: Int) {
        self.source = source
        self.placement = placement
        self.errorDescription = errorDescription
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }

    public init(source: PaywallSource, placement: String, error: Error) {
        let metadata = AnalyticsErrorMetadata(error: error)
        self.source = source
        self.placement = placement
        self.errorDescription = metadata.humanReadableReason
        self.errorDomain = metadata.errorDomain
        self.errorCode = metadata.errorCode
    }
}

/// Logged once when the app's onboarding flow starts.
///
/// Used as a top-of-funnel anchor event in acquisition and conversion dashboards.
/// Call ``PurchasesAndAnalytics/logOnboardingStarted()`` from the host app when
/// onboarding begins.
///
/// Event name: `Onboarding_Started`
public struct OnboardingStartedEvent: EventProtocol {

    public var name: String { "Onboarding_Started" }

    public var params: [String: Any] { [:] }

    public init() {}
}
