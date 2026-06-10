import Foundation
import os
import Sentry

enum Log {
    
    private static var logger = Logger(subsystem: "AnalyticsPackage", category: "")
    
    enum Level {
        case debug
        case analytics
        case error
        
        var prefix: String {
            switch self {
            case .analytics: return "[ANALYTICS]: "
            case .debug: return "[DEBUG]: "
            case .error: return "[ERROR]: "
            }
        }
        
        var sentryLevel: SentryLevel {
            switch self {
            case .analytics: return .info
            case .debug: return .debug
            case .error: return .error
            }
        }
    }
    
    static func printLog(l: Level, str: String) {
        let message = "\(l.prefix)\(str)"
        print(message)
        logger.notice("\(message, privacy: .public)")
        
        let breadcrumb = Breadcrumb(level: l.sentryLevel, category: "log")
        breadcrumb.message = message
        SentrySDK.addBreadcrumb(breadcrumb)
        
        if l == .error {
            SentrySDK.capture(message: message)
        }
    }
}
