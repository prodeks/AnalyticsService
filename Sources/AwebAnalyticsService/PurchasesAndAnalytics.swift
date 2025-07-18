import UIKit

@MainActor public class PurchasesAndAnalytics {

    public lazy var analytics: AnalyticsServiceProtocol = _analytics
    public lazy var purchases: PurchaseServiceProtocol = _purchases
    public lazy var paywalls: PaywallServiceProtocol = _paywalls
    public lazy var remoteConfig: RemoteConfigServiceProtocol = _remoteConfig
    
    lazy var _analytics = AnalyticsService()
    lazy var _purchases = PurchaseService()
    lazy var _paywalls = PaywallService(purchaseService: _purchases, analyticsService: _analytics)
    lazy var _remoteConfig = RemoteConfigService.shared
    
    /// Set this value before accessing the `analytics`
    public var dataFetchComplete: (([UIApplication.LaunchOptionsKey: Any]?) -> Void)?
    
    public static let shared = PurchasesAndAnalytics()
    
    private init() {
        _purchases.logEvent = self.log
        
        _analytics.analyticsStarted = { options in
            Task {
                await self._analytics.firebaseSignIn(options)
                await self._paywalls.fetchPaywallsAndProducts()
                await self._purchases.verifySubscriptionIfNeeded()
                await self._remoteConfig.fetch()
                await MainActor.run {
                    self.dataFetchComplete?(options)
                }
            }
        }
    }
    
    func log(_ e: EventProtocol) {
        analytics.log(e: e)
    }
}
