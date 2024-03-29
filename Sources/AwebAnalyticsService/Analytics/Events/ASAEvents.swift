import Foundation

struct ASAAttributionEvent: EventProtocol {
    var name: String {
        "did_receive_asa_attribution"
    }
    
    let params: [String : Any]
}

struct ASAAttributionErrorEvent: EventProtocol {
    
    var name: String {
        "did_receive_asa_attribution_error"
    }
    
    let description: String
    
    var params: [String : Any] {
        ["desription": description]
    }
}
