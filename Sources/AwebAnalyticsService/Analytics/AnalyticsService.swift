import Foundation
import FirebaseAnalytics
import FirebaseCore
import AppTrackingTransparency
import FacebookCore
import ApphudSDK
import AdServices
import ASATools
import BranchSDK
import AdSupport
import UserNotifications

//public protocol AnalyticsServiceProtocol: AnyObject {
//    func didFinishLaunchingWithOptions(application: UIApplication, options: [UIApplication.LaunchOptionsKey: Any]?)
//    func applicationDidBecomeActive(_ application: UIApplication)
//    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any]) -> Bool
//    func application(_application: UIApplication, continue userActivity: NSUserActivity) -> Bool
//    func application(_application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) -> Void
//    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
//    
//    func registerForNotifications()
//    func log(e: EventProtocol)
//    var apphudStarted: (() -> Void)? { get set }
//}

public class AnalyticsService: NSObject {

    private let firebase = Analytics.self
    private let branch = Branch.getInstance()
    private let apphud = Apphud.self
    private let asaTools = ASATools.instance
    
    let userID = AppEvents.shared.anonymousID
    
    let apphudStarted: () -> Void
    let setPlacements: ([ApphudPlacement]) -> Void
    
    init(
        apphudStarted: @escaping () -> Void,
        setPlacements: @escaping ([ApphudPlacement]) -> Void
    ) {
        self.apphudStarted = apphudStarted
        self.setPlacements = setPlacements
    }
    
    @MainActor func didFinishLaunchingWithOptions(
        application: UIApplication,
        options: [UIApplication.LaunchOptionsKey: Any]?
    ) {
        FirebaseApp.configure()
        
        branch.setIdentity(Apphud.deviceID())
        branch.initSession(launchOptions: options) { (params, error) in
            Log.printLog(l: .analytics, str: String(describing: params))
        }
        
        apphud.start(apiKey: PurchasesAndAnalytics.Keys.apphudKey) { user in
            self.apphud.placementsDidLoadCallback { placements in
                self.logPlacements(placements)
                self.setPlacements(placements)
                self.apphudStarted()
            }
        }
        
        asaTools.attribute(apiToken: PurchasesAndAnalytics.Keys.asatoolsKey) { response, error in
            if let response {
                let firebaseProperties = response.analyticsValues()
                firebaseProperties.forEach { key, value in
                    self.firebase.setUserProperty(String(describing: value), forName: key)
                }
                self.log(e: ASAAttributionEvent(params: firebaseProperties))
            } else if let error = error {
                self.log(e: ASAAttributionErrorEvent(description: error.localizedDescription))
            }
        }
        
        let userID = Apphud.userID()
        firebase.setUserID(userID)
        if let instanceID = firebase.appInstanceID() {
            apphud.addAttribution(
                data: nil,
                from: .firebase,
                identifer: instanceID,
                callback: nil
            )
        }
        
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: options
        )
    }
    
    func logPlacements(_ apphudPlacements: [ApphudPlacement]) {
        var str = "AppHud placements received:\n"
        apphudPlacements.forEach { placement in
            str.append("- \(placement.identifier), paywall - \(placement.paywall?.identifier ?? "missing")\n")
        }
        Log.printLog(l: .debug, str: "\n\n\n\(str)\n\n")
    }
    
    func registerForNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
            // handle if needed
        }
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any]
    ) -> Bool {
        branch.application(app, open: url, options: options)
        return ApplicationDelegate.shared.application(
            app,
            open: url,
            sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String,
            annotation: options[UIApplication.OpenURLOptionsKey.annotation]
        )
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        apphud.submitPushNotificationsToken(token: deviceToken, callback: nil)
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .notDetermined:
            ATTrackingManager.requestTrackingAuthorization { status in
                Log.printLog(l: .debug, str: "IDFA status: \(status)")
                DispatchQueue.global(qos: .default).async {
                    let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                    Apphud.setAdvertisingIdentifier(idfa)
                    if #available(iOS 14.3, *) {
                        if let token = try? AAAttribution.attributionToken() {
                            DispatchQueue.main.async {
                                Apphud.addAttribution(
                                    data: nil,
                                    from: .appleAdsAttribution,
                                    identifer: token,
                                    callback: nil
                                )
                            }
                        }
                    }
                }
            }
        default:
            break
        }
    }
    
    public func application(_application: UIApplication, continue userActivity: NSUserActivity) -> Bool {
        branch.continue(userActivity)
        return true
    }
    
    @MainActor func application(_application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) {
        apphud.handlePushNotification(apsInfo: userInfo)
        branch.handlePushNotification(userInfo)
    }
    
    func log(e: EventProtocol) {
    
        Log.printLog(l: .analytics, str: e.name + " \(e.params)")
        
        if let paywallOpenEvent = e as? PaywallOpenEvent {
            Task {
                let paywalls = await apphud.placements().compactMap { $0.paywall }
                if let p = paywalls.first(where: { $0.identifier == paywallOpenEvent.paywallID }) {
                    apphud.paywallShown(p)
                }
            }
            
            return
        }
        if let paywallClosedEvent = e as? PaywallClosedEvent {
            Task {
                let paywalls = await apphud.placements().compactMap { $0.paywall }
                if let p = paywalls.first(where: { $0.identifier == paywallClosedEvent.paywallID }) {
                    apphud.paywallClosed(p)
                }
            }
            return
        }
        
        firebase.logEvent(e.name, parameters: e.params)
        
        if let _ = e as? OnboardingStartedEvent {
            let event = BranchEvent(name: e.name)
            event.customData = [:]
            event.logEvent()
        }
        
        var fbParams: [AppEvents.ParameterName: Any] = [:]
        e.params.forEach { k, v in
            fbParams[AppEvents.ParameterName.init(k)] = v
        }
        
        AppEvents.shared.logEvent(AppEvents.Name(e.name), parameters: fbParams)
        
        if let purchaseEvent = e as? PurchaseEvent,
            case let .success(iap) = purchaseEvent {
            AppEvents.shared.logPurchase(
                amount: Double(iap.price),
                currency: "USD"
            )
            let event = BranchEvent.standardEvent(.purchase)
            event.currency = .USD
            event.eventDescription = iap.productID
            event.revenue = NSDecimalNumber(value: iap.price)
            event.logEvent()
        }
    }
}

extension AnalyticsService: UNUserNotificationCenterDelegate {
    @MainActor public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        apphud.handlePushNotification(apsInfo: response.notification.request.content.userInfo)
        completionHandler()
    }
    @MainActor public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        apphud.handlePushNotification(apsInfo: notification.request.content.userInfo)
        completionHandler([])
    }
}
