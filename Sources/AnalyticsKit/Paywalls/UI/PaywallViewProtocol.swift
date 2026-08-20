import UIKit

public protocol PaywallViewProtocol: UIView {
    var delegate: PaywallViewDelegateProtocol? { get set }
    var paywallID: any PaywallScreenProtocol { get }
}
