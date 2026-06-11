import Foundation
import os
import Sentry
import Adapty

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
        let message = "-->\(l.prefix)\(str)"
        NSLog(message)
        logger.notice("\(message, privacy: .public)")
        
        let breadcrumb = Breadcrumb(level: l.sentryLevel, category: "log")
        breadcrumb.message = message
        SentrySDK.addBreadcrumb(breadcrumb)
        
        if l == .error {
            SentrySDK.capture(message: message)
        }
    }
}

extension Log.Level {
    init(_ adaptyType: AdaptyLog.Level) {
        switch adaptyType {
        case .debug: self = .debug
        case .error: self = .error
        case .verbose: self = .debug
        case .warn: self = .debug
        case .info: self = .debug
        }
    }
}
