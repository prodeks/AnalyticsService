import Foundation

public class PurchasesAndAnalytics {

    public lazy var analytics = AnalyticsService()
    public lazy var purchases = PurchaseService()
    public lazy var paywalls = PaywallService()
    
    /// Set this value before accessing the `analytics`
    public var dataFetchComplete: (() -> Void)?
    
    private init() {
        purchases.logEvent = self.log
        
        analytics.analyticsStarted = { options in
            Task {
                await self.analytics.firebaseSignIn(options)
                let products = await self.purchases.getProducts()
                self.paywalls.products = products
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
    
    public func getPaywallController<V: PaywallViewProtocol>() -> PaywallController<V> {
        return PaywallController<V>(purchaseService: purchases)
    }
}
