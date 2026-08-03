import Foundation

/// The base contract for every analytics event in the system.
///
/// Conforming types describe a single user action or system occurrence that should be
/// forwarded to one or more analytics backends (Firebase, Facebook, AppsFlyer,
/// Mixpanel, etc.) via `AnalyticsService.log(e:)`.
///
/// ## Implementing a new event
///
/// ```swift
/// struct MyFeatureUsedEvent: EventProtocol {
///     var name: String { "my_feature_used" }
///     var params: [String: Any] { ["feature_id": featureID] }
///     let featureID: String
/// }
/// ```
///
/// Keep `name` stable across releases — changing it breaks historical dashboards.
/// Parameter keys should follow snake_case to stay consistent with Firebase conventions.
public protocol EventProtocol {

    /// The event name forwarded verbatim to every analytics backend.
    ///
    /// Must be stable, unique, and match any dashboard queries that rely on it.
    /// Firebase limits names to 40 characters; stay within that budget for
    /// cross-backend consistency.
    var name: String { get }

    /// Arbitrary key-value pairs that describe the event's context.
    ///
    /// Values must be serialisable types accepted by all backends (`String`, `Int`,
    /// `Double`, `Float`, `Bool`). Avoid nesting complex objects — flatten them into
    /// separate keys.
    var params: [String: Any] { get }
}

/// Logged when an analytics / subscription SDK setup step fails during cold start.
///
/// Event name: `analytics_setup_failed`
struct AnalyticsSetupFailedEvent: EventProtocol {

    var name: String { "analytics_setup_failed" }

    /// Stable snake_case key identifying the failing operation.
    let operation: String

    /// Human-readable description of the underlying error.
    let errorDescription: String

    /// The `NSError.domain` of the underlying error.
    let errorDomain: String

    /// The numeric error code from the underlying error.
    let errorCode: Int

    var params: [String: Any] {
        [
            "operation": operation,
            "error_description": errorDescription,
            "error_domain": errorDomain,
            "error_code": errorCode
        ]
    }

    init(operation: String, error: Error) {
        let nsError = error as NSError
        self.operation = operation
        self.errorDescription = error.localizedDescription
        self.errorDomain = nsError.domain
        self.errorCode = nsError.code
    }
}
