import Foundation
import FirebaseAnalytics
import FirebaseCore
import AppTrackingTransparency
import FacebookCore
import AdServices
import FirebaseAuth
import AdSupport
import UserNotifications
import Adapty
import AdaptyUI
import FirebaseMessaging
import Combine
import AppsFlyerLib
import PurchaseConnector
import Mixpanel
import FirebaseFirestore
import AdjustSdk

public protocol AnalyticsServiceProtocol: AnyObject {
    func setupAnalyticsIfNeeded(options: [UIApplication.LaunchOptionsKey: Any]?)
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
    var _userID: String { get set }
    var attributionData: AnyPublisher<[AnyHashable : Any], Never> { get }
}

class AnalyticsService: NSObject, AnalyticsServiceProtocol {

    private let firebase = Analytics.self
    private let adapty = Adapty.self
    private let adaptyUI = AdaptyUI.self
    private let appsflyer = AppsFlyerLib.shared()
    private let purchaseConnector = PurchaseConnector.shared()
    
    @Published public var _userID = ""
    public var userID: AnyPublisher<String, Never> {
        $_userID.eraseToAnyPublisher()
    }
    @Published private var _attributionData = [AnyHashable : Any]()
    public var attributionData: AnyPublisher<[AnyHashable : Any], Never> {
        $_attributionData.eraseToAnyPublisher()
    }
    
    public var analyticsStarted: (([UIApplication.LaunchOptionsKey: Any]?) -> Void)?
    private var didSetupAnalytics = false
    
    public func setupAnalyticsIfNeeded(options: [UIApplication.LaunchOptionsKey: Any]?) {
        if !didSetupAnalytics {
            appsflyer.appsFlyerDevKey = PurchasesAndAnalytics.Keys.appsflyerKey ?? ""
            appsflyer.appleAppID = PurchasesAndAnalytics.Keys.appID ?? ""
            appsflyer.delegate = self
            appsflyer.deepLinkDelegate = self
            appsflyer.isDebug = true
            appsflyer.waitForATTUserAuthorization(timeoutInterval: 60)
            purchaseConnector.purchaseRevenueDelegate = self
            purchaseConnector.purchaseRevenueDataSource = self
            purchaseConnector.autoLogPurchaseRevenue = .autoRenewableSubscriptions
            
            FirebaseApp.configure()
            
            Mixpanel.initialize(token: PurchasesAndAnalytics.Keys.mixPanelToken ?? "", trackAutomaticEvents: false)
            Mixpanel.mainInstance().loggingEnabled = true
            
            Messaging.messaging().delegate = self
            didSetupAnalytics = true
        }

        analyticsStarted?(options)
    }
    
    public func didFinishLaunchingWithOptions(
        application: UIApplication,
        options: [UIApplication.LaunchOptionsKey: Any]?
    ) {
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: options
        )
        
        setupAnalyticsIfNeeded(options: options)
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
                    try await Adapty.setIntegrationIdentifier(
                        key: "firebase_app_instance_id",
                        value: appInstanceId
                    )
                }
                
                try await Adapty.setIntegrationIdentifier(
                    key: "mixpanel_user_id",
                    value: Mixpanel.mainInstance().distinctId
                )
                
                try await Adapty.setIntegrationIdentifier(
                    key: "facebook_anonymous_id",
                    value: AppEvents.shared.anonymousID
                )
                
                initAdjust()
            }
        } catch {
            Log.printLog(l: .error, str: error.localizedDescription)
        }
    }
    
    func initAdjust() {
        
#if DEBUG
        let environment = ADJEnvironmentSandbox
        let adjustConfig = ADJConfig(
            appToken: PurchasesAndAnalytics.Keys.adjustKey ?? "",
            environment: environment)
        adjustConfig?.logLevel = ADJLogLevel.verbose
        adjustConfig?.delegate = self
#else
        let environment = ADJEnvironmentProduction
        let adjustConfig = ADJConfig(
            appToken: PurchasesAndAnalytics.Keys.adjustKey ?? "",
            environment: environment)
        adjustConfig?.logLevel = ADJLogLevel.suppress
        adjustConfig?.delegate = self
#endif
        
        Adjust.initSdk(adjustConfig)
        
        Task {
            let (adid, attribution) = await (Adjust.adid(), Adjust.attribution()?.dictionary())
            do {
                if let adid {
                    try await Adapty.setIntegrationIdentifier(key: "adjust_device_id", value: adid)
                }
                if let attribution {
                    try await Adapty.updateAttribution(attribution, source: "adjust")
                    _attributionData = attribution
                }
                
                // Log adjust info
                let firebaseAppInstanceId = Analytics.appInstanceID() ?? ""
                await sendAttributionWebhook(
                    storeId: PurchasesAndAnalytics.Keys.appID ?? "",
                    firebaseAppInstanceId: firebaseAppInstanceId,
                    adjustDeviceId: adid ?? "",
                    source: "adjust",
                    attribution: attribution ?? [:]
                )
            } catch {
                Log.printLog(l: .error, str: error.localizedDescription)
            }
        }
    }
    
    private func sendAttributionWebhook(
        storeId: String,
        firebaseAppInstanceId: String,
        adjustDeviceId: String,
        source: String,
        attribution: [AnyHashable: Any]
    ) async {
        let webhookURL = "https://adapty-attributions-420095526567.europe-west1.run.app/webhook"
        let authToken = "1dac2f40da774e43344f88eaee0ad566742d73f803f0a88d42626b803d55b085"
        
        guard let url = URL(string: webhookURL) else {
            Log.printLog(l: .error, str: "Invalid webhook URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "store_id": storeId,
            "firebase_app_instance_id": firebaseAppInstanceId,
            "adjust_device_id": adjustDeviceId,
            "source": source,
            "attribution": attribution
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    Log.printLog(l: .debug, str: "Attribution webhook sent successfully")
                } else {
                    Log.printLog(l: .error, str: "Attribution webhook failed with status code: \(httpResponse.statusCode)")
                }
            }
        } catch {
            Log.printLog(l: .error, str: "Failed to send attribution webhook: \(error.localizedDescription)")
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
        // Forward deep link to Adjust for attribution
        if let adjustDeeplink = ADJDeeplink(deeplink: url) {
            Adjust.processDeeplink(adjustDeeplink)
        }
        Log.printLog(l: .debug, str: "Adjust URL scheme deep link processed: \(url.absoluteString)")
        
        // Store direct deep link for app to handle
        _attributionData = [PurchasesAndAnalytics.Keys.adjustDeeplinkKey: url.absoluteString]
        
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
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL,
            let adjustDeeplink = ADJDeeplink(deeplink: url) {
            
            Adjust.processDeeplink(adjustDeeplink)
            Log.printLog(l: .debug, str: "Adjust Universal Link processed: \(url.absoluteString)")
            
            // Store direct deep link for app to handle
            _attributionData = [PurchasesAndAnalytics.Keys.adjustDeeplinkKey: url.absoluteString]
        }
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
        
        let params = e.params.mapValues { String.init(describing: $0) }
        Mixpanel.mainInstance().track(event: e.name, properties: params)
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
        
        let afUID = AppsFlyerLib.shared().getAppsFlyerUID()
        Adapty.setIntegrationIdentifier(key: "appsflyer_id", value: afUID)
        Adapty.updateAttribution(conversionInfo, source: "appsflyer")
    }
    
    public func onConversionDataFail(_ error: any Error) {
        Log.printLog(l: .error, str: error.localizedDescription)
    }

    public func didResolveDeepLink(_ result: DeepLinkResult) {
        if let deeplinkValue = result.deepLink?.deeplinkValue {
            _attributionData = ["deep_link_value": deeplinkValue]
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

// MARK: - AdjustDelegate
extension AnalyticsService: AdjustDelegate {
    func adjustAttributionChanged(_ attribution: ADJAttribution?) {
        print(attribution)
    }
    
    func adjustSkanUpdated(withConversionData data: [String : String]) {
        _attributionData = ["adjust_deferred_deeplink": data]
    }
    
    func adjustDeferredDeeplinkReceived(_ deeplink: URL?) -> Bool {
        if let deeplink {
            _attributionData = [PurchasesAndAnalytics.Keys.adjustDeeplinkKey: deeplink.absoluteString]
        }
        return false
    }
}
