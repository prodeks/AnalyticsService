import Foundation
import Adapty

/// Normalises Adapty errors into a flat, analytics-friendly representation.
///
/// The `reason` string is a short key suitable for grouping related failures in
/// dashboards (e.g. `"cancelled"`, `"network_error"`, `"payment_invalid"`). The
/// domain and code are forwarded verbatim from the underlying `NSError` so that
/// support tooling can cross-reference them with App Store Connect.
struct PaywallFailureMetadata {
    let reason: PaywallFailureReason
    let errorDomain: String
    let errorCode: Int

    var reasonRawValue: String { reason.rawValue }

    init(error: AdaptyError) {
        let nsError = error as NSError
        self.reason = Self.reason(error: error, nsError: nsError)
        self.errorDomain = nsError.domain
        self.errorCode = error.errorCode
    }

    private init(reason: PaywallFailureReason, errorDomain: String, errorCode: Int) {
        self.reason = reason
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }

    /// Pre-built metadata for a user-initiated cancellation.
    static var cancelled: PaywallFailureMetadata {
        PaywallFailureMetadata(
            reason: .cancelled,
            errorDomain: "AdaptyError",
            errorCode: AdaptyError.ErrorCode.paymentCancelled.rawValue
        )
    }

    private static func reason(error: AdaptyError, nsError: NSError) -> PaywallFailureReason {
        if error.errorCode == AdaptyError.ErrorCode.paymentCancelled.rawValue {
            return .cancelled
        } else if isNetworkError(nsError) {
            return .networkError
        } else {
            return .paymentInvalid
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
