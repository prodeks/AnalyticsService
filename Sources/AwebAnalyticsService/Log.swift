import Foundation
import os

enum Log {
    
    private static var logger = Logger(subsystem: "AnalyticsPackage", category: "")
    
    enum Level {
        case debug
        case analytics
        case error
        
        var prefix: String {
            switch self {
            case .analytics: return "--> [ANALYTICS]: "
            case .debug: return "--> [DEBUG]: "
            case .error: return "--> [ERROR]: "
            }
        }
    }
    
    static func printLog(l: Level, str: String) {
        print("\(l.prefix)\(str)")
    }
}
