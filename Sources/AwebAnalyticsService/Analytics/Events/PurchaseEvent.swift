import Foundation
import Firebase
import FacebookCore

enum PurchaseEvent: EventProtocol {
    var name: String {
        switch self {
        case .cancel: return "sale_confirmation_cancel"
        case .success: return "sale_confirmation_success"
        case .fail: return "sale_confirmation_fail"
        case .restore: return "sale_confirmation_restore"
        }
    }
    
    var params: [String : Any] {
        switch self {
        case .success(let iap):
            return ["product_id": iap.0, AnalyticsParameterValue: iap.0]
        case .cancel(let iap):
            return ["product_id": iap.0, AnalyticsParameterValue: iap.0]
        case .fail(let iap):
            return ["product_id": iap.0, AnalyticsParameterValue: iap.0]
        case .restore:
            return [:]
        }
    }
    
    case success(iap: (String, Float))
    case cancel(iap: (String, Float))
    case fail(iap: (String, Float))
    case restore
}
