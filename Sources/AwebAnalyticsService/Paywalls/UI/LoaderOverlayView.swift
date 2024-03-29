import UIKit
import Lottie

class LoaderOverlayView: UIView {
    
    let spinner = LottieAnimationView(name: "spinner")
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .black.withAlphaComponent(0.2)
        addSubview(spinner)
        spinner.loopMode = .loop
        spinner.play()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        spinner.center = center
    }
}
