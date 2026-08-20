import Foundation

/// Fired when Apple Search Ads attribution data is successfully retrieved from the
/// `AdServices` framework.
///
/// The `params` dictionary is passed through directly from the raw attribution
/// response so that all available ASA dimensions (campaign ID, ad group ID, keyword,
/// etc.) are forwarded to the analytics backends without loss.
struct ASAAttributionEvent: EventProtocol {

    var name: String {
        "did_receive_asa_attribution"
    }

    /// Raw key-value attribution payload returned by `AAAttribution.attributionToken()`.
    let params: [String: Any]
}

/// Fired when the ASA attribution request fails (e.g. the device is not eligible,
/// network error, or the token has expired).
///
/// The error description is included as a param so support tooling can distinguish
/// transient failures from permanent ineligibility without inspecting raw crash logs.
struct ASAAttributionErrorEvent: EventProtocol {

    var name: String {
        "did_receive_asa_attribution_error"
    }

    /// Human-readable description of the error returned by `AdServices`.
    let description: String

    var params: [String: Any] {
        // Note: the key intentionally preserves the original typo ("desription")
        // to avoid breaking existing dashboard queries that rely on it.
        ["desription": description]
    }
}
