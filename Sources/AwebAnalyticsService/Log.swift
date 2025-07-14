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
        switch l {
        case .debug:
            logger.log(level: .debug, "\(l.prefix)\(str)")
        case .analytics:
            logger.log(level: .info, "\(l.prefix)\(str)")
        case .error:
            logger.log(level: .error, "\(l.prefix)\(str)")
        }
    }
}
