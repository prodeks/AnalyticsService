import FirebaseRemoteConfig

public protocol RemoteConfigServiceProtocol {
    func getString<K: RawRepresentable>(_ key: K) -> String? where K.RawValue == String
    func getInt<K: RawRepresentable>(_ key: K) -> Int where K.RawValue == String
    func getBool<K: RawRepresentable>(_ key: K) -> Bool where K.RawValue == String
}

class RemoteConfigService: RemoteConfigServiceProtocol {
    
    let remoteConfig: RemoteConfig
    
    static let shared = RemoteConfigService()

    private init() {
        remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 0
        remoteConfig.configSettings = settings
    }
    
    public func getInt<K: RawRepresentable>(_ key: K) -> Int where K.RawValue == String {
        let value = remoteConfig.configValue(forKey: key.rawValue)
        let stringValue = value.numberValue.intValue
        return stringValue
    }
    
    public func getString<K: RawRepresentable>(_ key: K) -> String? where K.RawValue == String {
        let value = remoteConfig.configValue(forKey: key.rawValue)
        let stringValue = value.stringValue
        return stringValue
    }
    
    public func getBool<K: RawRepresentable>(_ key: K) -> Bool where K.RawValue == String {
        let value = remoteConfig.configValue(forKey: key.rawValue)
        let boolValue = value.boolValue
        return boolValue
    }
    
    func fetch() async {
        return await withCheckedContinuation { continuation in
            fetch {
                continuation.resume()
            }
        }
    }
    
    func fetch(_ completion: @escaping () -> Void) {
        remoteConfig.fetch { status, error in
            Log.printLog(l: .debug, str: status.description)
            if let error {
                Log.printLog(l: .error, str: error.localizedDescription)
            }
            
            if status == .success {
                self.remoteConfig.activate { _, error in
                    if let error {
                        Log.printLog(l: .error, str: error.localizedDescription)
                    } else {
                        Log.printLog(l: .debug, str: "Remote config activated")
                    }
                    completion()
                }
            } else {
                completion()
            }
        }
    }
}

extension RemoteConfigFetchStatus {
    var description: String {
        switch self {
        case .failure:
            return "Remote Config Status: Fetch failed"
        case .noFetchYet:
            return "Remote Config Status: No fetch yet"
        case .success:
            return "Remote Config Status: Fetch success"
        case .throttled:
            return "Remote Config Status: Fetch throttled"
        @unknown default:
            return ""
        }
    }
}
