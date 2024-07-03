import Foundation
import FirebaseAnalytics
import FirebaseCore
import AppTrackingTransparency
import FacebookCore
import AdServices
import FirebaseAuth
import ASATools
import BranchSDK
import AdSupport
import UserNotifications
import Adapty

public protocol AnalyticsServiceProtocol: AnyObject {
    func didFinishLaunchingWithOptions(application: UIApplication, options: [UIApplication.LaunchOptionsKey: Any]?)
    func applicationDidBecomeActive(_ application: UIApplication)
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any]) -> Bool
    func application(_application: UIApplication, continue userActivity: NSUserActivity) -> Bool
    func application(_application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) -> Void
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    
    func registerForNotifications()
    func log(e: EventProtocol)
}

public class AnalyticsService: NSObject, AnalyticsServiceProtocol {

    private let firebase = Analytics.self
    private let branch = Branch.getInstance()
    private let asaTools = ASATools.instance
    private let adapty = Adapty.self
    
    public var analyticsStarted: (([UIApplication.LaunchOptionsKey: Any]?) -> Void)?
    
    @MainActor public func didFinishLaunchingWithOptions(
        application: UIApplication,
        options: [UIApplication.LaunchOptionsKey: Any]?
    ) {
        FirebaseApp.configure()
        
        if let key = PurchasesAndAnalytics.Keys.asatoolsKey {
            asaTools.attribute(apiToken: key) { response, error in
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
        }
        
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: options
        )
        
        analyticsStarted?(options)
    }
    
    func firebaseSignIn(_ options: [UIApplication.LaunchOptionsKey : Any]?) async {
        await withCheckedContinuation { c in
            Auth.auth().signInAnonymously { result, error in
                if let result {
                    let userID = result.user.uid
                    
                    if let key = PurchasesAndAnalytics.Keys.subscriptionServiceKey {
                        self.adapty.activate(key, customerUserId: userID)
                        
                        if let appInstanceId = Analytics.appInstanceID() {
                            let builder = AdaptyProfileParameters.Builder()
                                .with(firebaseAppInstanceId: appInstanceId)
                                    
                            self.adapty.updateProfile(params: builder.build()) { error in
                                if let error {
                                    Log.printLog(l: .analytics, str: error.localizedDescription)
                                }
                            }
                        }
                    }
                    self.branch.setIdentity(userID)
                    self.branch.initSession(launchOptions: options) { (params, error) in
                        Log.printLog(l: .analytics, str: String(describing: params))
                    }
                    
                    self.firebase.setUserID(userID)
                }
                c.resume()
            }
        }
    }
    
    public func registerForNotifications() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
            // handle if needed
        }
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    public func application(
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

    public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        
    }
    
    public func applicationDidBecomeActive(_ application: UIApplication) {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .notDetermined:
            ATTrackingManager.requestTrackingAuthorization { status in
                Log.printLog(l: .debug, str: "IDFA status: \(status)")
                DispatchQueue.global(qos: .default).async {
                    let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                    if #available(iOS 14.3, *) {
                        if let token = try? AAAttribution.attributionToken() {
                            
                        }
                    }
                }
            }
        default:
            break
        }
    }
    
    public func application(
        _application: UIApplication,
        continue userActivity: NSUserActivity
    ) -> Bool {
        branch.continue(userActivity)
        return true
    }
    
    @MainActor public func application(
        _application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any]
    ) {
        branch.handlePushNotification(userInfo)
    }
    
    public func log(e: EventProtocol) {
    
        Log.printLog(l: .analytics, str: e.name + " \(e.params)")
        
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
                amount: Double(iap.1),
                currency: "USD"
            )
            let event = BranchEvent.standardEvent(.purchase)
            event.currency = .USD
            event.eventDescription = iap.0
            event.revenue = NSDecimalNumber(value: iap.1)
            event.logEvent()
        }
    }
}

extension AnalyticsService: UNUserNotificationCenterDelegate {
    @MainActor public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    @MainActor public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}
