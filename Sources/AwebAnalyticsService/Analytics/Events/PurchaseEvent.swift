import Foundation
import Firebase
import FacebookCore
import StoreKit
import Adapty

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
            return ["product_id": iap.0, AnalyticsParameterValue: iap.1]
        case .cancel(let iap):
            return ["product_id": iap.0, AnalyticsParameterValue: iap.1]
        case .fail(let iap):
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
    
    case success(iap: (String, Float))
    case cancel(iap: (String, Float))
    case fail(iap: (String, AdaptyError))
    case restore
}
