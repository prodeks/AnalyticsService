import Foundation
import Firebase
import FacebookCore
import StoreKit
import Adapty

/// Represents the four possible outcomes of an in-app purchase attempt.
///
/// These events are logged to every analytics backend via `AnalyticsService.log(e:)`.
/// The Firebase backend additionally logs a purchase revenue event for `.success` via
/// `AppEvents.shared.logPurchase(amount:currency:)`.
///
/// ## Event names (stable — do not rename)
/// | Case | Firebase / FB / AF name |
/// |---|---|
/// | `.success` | `sale_confirmation_success` |
/// | `.cancel` | `sale_confirmation_cancel` |
/// | `.fail` | `sale_confirmation_fail` |
/// | `.restore` | `sale_confirmation_restore` |
enum PurchaseEvent: EventProtocol {

    /// The purchase completed successfully.
    ///
    /// - Parameter iap: A tuple of `(productID, price)` in USD. The price is used by
    ///   `AnalyticsService` to log revenue to Facebook.
    case success(iap: (String, Float))

    /// The user cancelled the purchase dialog before payment was authorised.
    ///
    /// - Parameter iap: A tuple of `(productID, price)`. Price is preserved so
    ///   cancelled checkout funnels can be valued the same way as completions.
    case cancel(iap: (String, Float))

    /// The purchase failed due to an Adapty or StoreKit error.
    ///
    /// - Parameter iap: A tuple of `(productID, AdaptyError)`. The error is serialised
    ///   into a multiline string containing the error code and all `userInfo` entries.
    case fail(iap: (String, AdaptyError))

    /// A restore-purchases operation completed.
    ///
    /// No product-level payload is attached because a restore may affect multiple
    /// products simultaneously and the authoritative state is derived from the profile
    /// returned by `Adapty.restorePurchases()`.
    case restore

    // MARK: - EventProtocol

    var name: String {
        switch self {
        case .cancel: return "sale_confirmation_cancel"
        case .success: return "sale_confirmation_success"
        case .fail: return "sale_confirmation_fail"
        case .restore: return "sale_confirmation_restore"
        }
    }

    var params: [String: Any] {
        switch self {
        case .success(let iap):
            return ["product_id": iap.0, AnalyticsParameterValue: iap.1]

        case .cancel(let iap):
            return ["product_id": iap.0, AnalyticsParameterValue: iap.1]

        case .fail(let iap):
            // Serialise the full error user-info into a single string value so that
            // backends that don't support nested objects (e.g. Firebase) still capture
            // all diagnostic detail.
            return ["product_id": iap.0, AnalyticsParameterValue: {
                let error = iap.1
                var str = ""
                str.append("code: \(error.errorCode)\n")
                error.errorUserInfo.forEach { k, v in
                    str.append("\(k): \(v)\n")
                }
                return str
            }()]

        case .restore:
            return [:]
        }
    }
}
