import Foundation

@MainActor
final class RegionalPaywallService: PaywallServiceProtocol {
    
    var placements = Set<String>() {
        didSet {
            adaptyPaywallService.placements = placements
            directStoreKitPaywallService.placements = placements
        }
    }
    
    var uiFactory: ((PaywallIdentifier) -> PaywallViewProtocol?)? {
        didSet {
            adaptyPaywallService.uiFactory = uiFactory
            directStoreKitPaywallService.uiFactory = uiFactory
        }
    }
    
    var viewIdentifiersByPlacement = [String: PaywallIdentifier]() {
        didSet {
            directStoreKitPaywallService.viewIdentifiersByPlacement = viewIdentifiersByPlacement
        }
    }
    
    private enum ActiveService {
        case adapty
        case directStoreKit
    }
    
    private let adaptyPaywallService: PaywallService
    private let directStoreKitPaywallService: DirectStoreKitPaywallService
    private var activeService: ActiveService = .adapty
    
    init(purchaseService: PurchaseService, analyticsService: AnalyticsService) {
        self.adaptyPaywallService = PaywallService(
            purchaseService: purchaseService,
            analyticsService: analyticsService
        )
        self.directStoreKitPaywallService = DirectStoreKitPaywallService(purchaseService: purchaseService)
    }
    
    func configure(isRunningInChina: Bool) {
        activeService = isRunningInChina ? .directStoreKit : .adapty
    }
    
    func getPaywall(_ placement: PaywallPlacementProtocol) -> PaywallControllerProtocol? {
        switch activeService {
        case .adapty:
            return adaptyPaywallService.getPaywall(placement)
        case .directStoreKit:
            return directStoreKitPaywallService.getPaywall(placement)
        }
    }
    
    func setFallbackPaywalls(url: URL) {
        adaptyPaywallService.setFallbackPaywalls(url: url)
    }
    
    func fetchPaywallsAndProducts() async {
        switch activeService {
        case .adapty:
            await adaptyPaywallService.fetchPaywallsAndProducts()
        case .directStoreKit:
            await directStoreKitPaywallService.fetchProducts()
        }
    }
}
