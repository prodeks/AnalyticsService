import Foundation

public class PurchasesAndAnalytics {

    public lazy var analytics = AnalyticsService()
    public lazy var purchases = PurchaseService()
    public lazy var paywalls = PaywallService(purchaseService: purchases)
    
    /// Set this value before accessing the `analytics`
    public var dataFetchComplete: (() -> Void)?
    
    private init() {
        purchases.logEvent = self.log
        
        analytics.analyticsStarted = { options in
            Task {
                await self.analytics.firebaseSignIn(options)
                await self.paywalls.fetchPaywallsAndProducts()
                await self.purchases.verifySubscriptionIfNeeded()
                await MainActor.run {
                    self.dataFetchComplete?()
                }
            }
        }
    }
    
    public static let shared = PurchasesAndAnalytics()
    
    func log(_ e: EventProtocol) {
        analytics.log(e: e)
    }
}
