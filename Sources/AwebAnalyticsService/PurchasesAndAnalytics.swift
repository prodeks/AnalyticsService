import Foundation

public class PurchasesAndAnalytics {

    lazy var analytics = AnalyticsService(apphudStarted: self.apphudStarted) { placements in
        self.paywalls.apphudPlacements = placements
    }
    lazy var purchases = PurchaseService()
    lazy var paywalls = PaywallService()
    
    public var apphudStarted: (() -> Void)!
    
    private init() {
        purchases.logEvent = self.log
    }
    public static let shared = PurchasesAndAnalytics()
    
    func log(_ e: EventProtocol) {
        analytics.log(e: e)
    }
    
}
