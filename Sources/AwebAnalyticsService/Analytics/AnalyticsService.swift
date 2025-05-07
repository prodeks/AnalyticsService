import Foundation
import FirebaseAnalytics
import FirebaseCore
import AppTrackingTransparency
import FacebookCore
import AdServices
import FirebaseAuth
import ASATools
import AdSupport
import UserNotifications
import Adapty
import AdaptyUI
import FirebaseMessaging
import Combine
import AppsFlyerLib
import PurchaseConnector

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
    var attributionData: AnyPublisher<[AnyHashable : Any], Never> { get }
}

public class AnalyticsService: NSObject, AnalyticsServiceProtocol {

    public static let deepLinkValueKey = "deepLinkValue"
    private let firebase = Analytics.self
    private let asaTools = ASATools.instance
    private let adapty = Adapty.self
    private let adaptyUI = AdaptyUI.self
    private let appsflyer = AppsFlyerLib.shared()
    private let purchaseConnector = PurchaseConnector.shared()
    
    @Published private var _userID = ""
    public var userID: AnyPublisher<String, Never> {
        $_userID.eraseToAnyPublisher()
    }
    @Published private var _attributionData = [AnyHashable : Any]()
    public var attributionData: AnyPublisher<[AnyHashable : Any], Never> {
        $_attributionData.eraseToAnyPublisher()
    }
    
    public var analyticsStarted: (([UIApplication.LaunchOptionsKey: Any]?) -> Void)?
    
    public func didFinishLaunchingWithOptions(
        application: UIApplication,
        options: [UIApplication.LaunchOptionsKey: Any]?
    ) {
        Task { @MainActor in
            appsflyer.appsFlyerDevKey = PurchasesAndAnalytics.Keys.appsflyerKey ?? ""
            appsflyer.appleAppID = PurchasesAndAnalytics.Keys.appID ?? ""
            appsflyer.delegate = self
            appsflyer.deepLinkDelegate = self
            appsflyer.isDebug = true
            purchaseConnector.purchaseRevenueDelegate = self
            purchaseConnector.purchaseRevenueDataSource = self
            purchaseConnector.autoLogPurchaseRevenue = .autoRenewableSubscriptions

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
    }
    
    func firebaseSignIn(_ options: [UIApplication.LaunchOptionsKey : Any]?) async {
        do {
            let signInResult = try await Auth.auth().signInAnonymously()
            let userID = signInResult.user.uid
            firebase.setUserID(userID)
            _userID = userID
            appsflyer.customerUserID = userID
            if let key = PurchasesAndAnalytics.Keys.subscriptionServiceKey {
                try await adapty.activate(key, customerUserId: userID)
                try await adaptyUI.activate()
                
                if let appInstanceId = Analytics.appInstanceID() {
                    let builder = AdaptyProfileParameters.Builder().with(firebaseAppInstanceId: appInstanceId)
                    try await adapty.updateProfile(params: builder.build())
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
        appsflyer.start()
        purchaseConnector.startObservingTransactions()
    }
    
    public func reqeuestATT() async -> ATTrackingManager.AuthorizationStatus {
        let result = await withTimeout(seconds: 2) {
            await withCheckedContinuation { c in
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
        return result ?? .notDetermined
    }
    
    public func application(
        _application: UIApplication,
        continue userActivity: NSUserActivity
    ) -> Bool {
        return true
    }
    
    public func application(
        _application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any]
    ) {
        Task { @MainActor in
            
        }
    }
    
    public func log(e: EventProtocol) {
    
        Log.printLog(l: .analytics, str: e.name + " \(e.params)")
        
        firebase.logEvent(e.name, parameters: e.params)
        
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
        }
        
        appsflyer.logEvent(e.name, withValues: e.params)
    }
}

extension AnalyticsService: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            completionHandler()
        }
    }
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            let userInfo = notification.request.content.userInfo
            Log.printLog(l: .debug, str: "Will present notification, userInfo \n\(userInfo)")
            completionHandler([.banner, .badge, .sound])
        }
    }
}

extension AnalyticsService: MessagingDelegate {
    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let fcmToken {
            Log.printLog(l: .debug, str: "Did receive FCM token - \(fcmToken)")
        }
    }
}

extension AnalyticsService: AppsFlyerLibDelegate, DeepLinkDelegate, PurchaseRevenueDelegate, PurchaseRevenueDataSource {
    public func onConversionDataSuccess(_ conversionInfo: [AnyHashable : Any]) {
        _attributionData = conversionInfo
    }
    
    public func onConversionDataFail(_ error: any Error) {
        Log.printLog(l: .error, str: error.localizedDescription)
    }

    public func didResolveDeepLink(_ result: DeepLinkResult) {
        if let deeplinkValue = result.deepLink?.deeplinkValue {
            _attributionData = [AnalyticsService.deepLinkValueKey: deeplinkValue]
        }
    }
    
    public func didReceivePurchaseRevenueValidationInfo(
        _ validationInfo: [AnyHashable : Any]?,
        error: (any Error)?
    ) {
        if let validationInfo {
            Log.printLog(l: .debug, str: "Purchase revenue validation info: \(validationInfo)")
        }
        if let error {
            Log.printLog(l: .error, str: error.localizedDescription)
        }
    }
    
    public func purchaseRevenueAdditionalParameters(
        for products: Set<SKProduct>,
        transactions: Set<SKPaymentTransaction>?
    ) -> [AnyHashable : Any]? {
        return nil
    }
}
