import UIKit
import StoreKit

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
                let isRunningInChina = await self.isRunningInChina()
                self._paywalls.isRunningInChina = isRunningInChina
                self._analytics.isRunningInChina = isRunningInChina
                await self._analytics.firebaseSignIn(options)
                
                async let paywallsTask: Void  = self._paywalls.fetchPaywallsAndProducts()
                async let subscriptionTask: Void  = self._purchases.verifySubscriptionIfNeeded()
                async let remoteConfigTask: Void  = self._remoteConfig.fetch()
                
                _ = await (paywallsTask, subscriptionTask, remoteConfigTask)
                
                await MainActor.run {
                    self.dataFetchComplete?(options)
                }
            }
        }
    }

    private func isRunningInChina() async -> Bool {
        let storefront = await Storefront.current?.countryCode
        let locale = Locale.current.region?.identifier
        
        return storefront == "CHN" || locale == "CN"
    }
    
    func log(_ e: EventProtocol) {
        analytics.log(e: e)
    }
}
