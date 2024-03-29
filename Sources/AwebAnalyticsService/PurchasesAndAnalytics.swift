import Foundation

public class PurchasesAndAnalytics {

    public lazy var analytics = AnalyticsService { placements in
        self.paywalls.apphudPlacements = placements
    }
    public lazy var purchases = PurchaseService()
    public lazy var paywalls = PaywallService()
    
    /// Set this value before accessing the `analytics`
    public var apphudStarted: (() -> Void)!
    
    private init() {
        purchases.logEvent = self.log
    }
    public static let shared = PurchasesAndAnalytics()
    
    func log(_ e: EventProtocol) {
        analytics.log(e: e)
    }
    
}
