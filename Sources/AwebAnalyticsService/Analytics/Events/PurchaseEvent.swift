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
            return ["product_id": iap.productID, AnalyticsParameterValue: iap.productID]
        case .cancel(let iap):
            return ["product_id": iap.productID, AnalyticsParameterValue: iap.productID]
        case .fail(let iap):
            return ["product_id": iap.productID, AnalyticsParameterValue: iap.productID]
        case .restore:
            return [:]
        }
    }
    
    case success(iap: IAPProtocol)
    case cancel(iap: IAPProtocol)
    case fail(iap: IAPProtocol)
    case restore
}
