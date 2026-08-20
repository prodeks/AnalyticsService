import UIKit
import WebKit

public protocol URLConvertable {
    func url() -> URL?
}

extension URL: URLConvertable {
    public func url() -> URL? {
        return self
    }
}

public class WebViewController: UIViewController {
    
    let webview = WKWebView()
    
    lazy var dismissItem = UIBarButtonItem(
        title: PurchasesAndAnalytics.Strings.dismiss,
        style: .plain, 
        target: self,
        action: #selector(modalDismiss)
    )
    
    public var item: URLConvertable? {
        didSet {
            if let url = item?.url() {
                webview.load(URLRequest(url: url))
            }
        }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.leftBarButtonItem = dismissItem
        view.backgroundColor = .white
        view.addSubview(webview)
        webview.frame = view.bounds
    }
    
    @objc func modalDismiss() {
        navigationController?.dismiss(animated: true)
    }
}

