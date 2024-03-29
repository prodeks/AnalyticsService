import Foundation

public protocol EventProtocol {
    var name: String { get }
    var params: [String: Any] { get }
}
