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
import AdaptyUI
import FirebaseMessaging
import Combine

public protocol AnalyticsServiceProtocol: AnyObject {
    func didFinishLaunchingWithOptions(application: UIApplication, options: [UIApplication.LaunchOptionsKey: Any]?)
    func applicationDidBecomeActive(_ application: UIApplication)
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any]) -> Bool
    func application(_application: UIApplication, continue userActivity: NSUserActivity) -> Bool
    func application(_application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) -> Void
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    
    func registerForNotifications()
    func log(e: EventProtocol)
    func reqeuestATT() async -> ATTrackingManager.AuthorizationStatus
    
    var userID: AnyPublisher<String, Never> { get }
    var branchData: AnyPublisher<[AnyHashable : Any], Never> { get }
}

public class AnalyticsService: NSObject, AnalyticsServiceProtocol {

    private let firebase = Analytics.self
    private let branch = Branch.getInstance()
    private let asaTools = ASATools.instance
    private let adapty = Adapty.self
    private let adaptyUI = AdaptyUI.self
    
    @Published private var _userID = ""
    public var userID: AnyPublisher<String, Never> {
        $_userID.eraseToAnyPublisher()
    }
    @Published private var _branchData = [AnyHashable : Any]()
    public var branchData: AnyPublisher<[AnyHashable : Any], Never> {
        $_branchData.eraseToAnyPublisher()
    }
    
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
        
        Messaging.messaging().delegate = self
        
        analyticsStarted?(options)
    }
    
    private func initBranchSession(launchOptions: [UIApplication.LaunchOptionsKey : Any]?) -> AsyncStream<[AnyHashable : Any]>  {
        return AsyncStream { continuation in
            self.branch.initSession(launchOptions: launchOptions) { (params, error) in
                Log.printLog(l: .analytics, str: String(describing: params))
                let unwrap = params ?? [:]
                continuation.yield(unwrap)
            }
        }
    }
    
    func firebaseSignIn(_ options: [UIApplication.LaunchOptionsKey : Any]?) async {
        do {
            let signInResult = try await Auth.auth().signInAnonymously()
            let userID = signInResult.user.uid
            firebase.setUserID(userID)
            _userID = userID
            if let key = PurchasesAndAnalytics.Keys.subscriptionServiceKey {
                try await adapty.activate(key, customerUserId: userID)
                try await adaptyUI.activate()
                
                if let appInstanceId = Analytics.appInstanceID() {
                    try await Adapty.setIntegrationIdentifier(
                        key: "firebase_app_instance_id",
                        value: appInstanceId
                    )
                }
            }
            branch.setIdentity(userID)
            Task {
                for await value in initBranchSession(launchOptions: options) {
                    _branchData = value
                }
            }
        } catch {
            Log.printLog(l: .error, str: error.localizedDescription)
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
        
    }
    
    public func reqeuestATT() async -> ATTrackingManager.AuthorizationStatus {
        return await withCheckedContinuation { c in
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.global(qos: .default).async {
                    let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
                    Log.printLog(l: .debug, str: "IDFA: \(idfa)")
                    let idfv = UIDevice.current.identifierForVendor?.uuidString ?? ""
                    Log.printLog(l: .debug, str: "IDFV: \(idfv)")
                    if let token = try? AAAttribution.attributionToken() {
                        Log.printLog(l: .debug, str: "AttributionToken: \(token)")
                    }
                }
                let builder = AdaptyProfileParameters.Builder().with(appTrackingTransparencyStatus: status)
                Task {
                    do {
                        try await Adapty.updateProfile(params: builder.build())
                        c.resume(returning: status)
                    } catch {
                        Log.printLog(l: .error, str: error.localizedDescription)
                    }
                }
            }
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
    @MainActor public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
    @MainActor public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        Log.printLog(l: .debug, str: "Will present notification, userInfo \n\(userInfo)")
        completionHandler([.banner, .badge, .sound])
    }
}

extension AnalyticsService: MessagingDelegate {
    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let fcmToken {
            Log.printLog(l: .debug, str: "Did receive FCM token - \(fcmToken)")
        }
    }
}
