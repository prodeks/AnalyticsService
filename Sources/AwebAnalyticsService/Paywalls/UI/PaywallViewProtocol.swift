import UIKit

public protocol PaywallViewProtocol: UIView {
    var delegate: PaywallViewDelegateProtocol? { get set }
    var appHudPaywallID: any PaywallScreenProtocol { get }
}
