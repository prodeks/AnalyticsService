import Foundation

public protocol IAPProtocol: CaseIterable {
    var productID: String { get }
    var price: Float { get }
}
