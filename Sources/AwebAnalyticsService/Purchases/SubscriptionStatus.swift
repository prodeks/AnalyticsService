import Adapty
import Foundation

public enum SubscriptionStatus: Codable {
    /// Active with no issues
    case active
    
    /// Active but billing issue detected (grace period)
    case activeBillingIssue(expiresAt: Date?)
    
    /// Inactive due to billing failure (current or past)
    case inactiveDueToBilling
    
    /// Inactive for other reasons (voluntary cancel, expired, etc.)
    case inactive
    
    public var isSubActive: Bool {
        switch self {
        case .active, .activeBillingIssue:
            return true
        case .inactive, .inactiveDueToBilling:
            return false
        }
    }
}

public extension AdaptyProfile.AccessLevel {
    var subscriptionStatus: SubscriptionStatus {
        if isActive {
            if billingIssueDetectedAt != nil || isInGracePeriod {
                return .activeBillingIssue(expiresAt: expiresAt)
            }
            return .active
        } else {
            if billingIssueDetectedAt != nil || cancellationReason == "billing_error" {
                return .inactiveDueToBilling
            }
            return .inactive
        }
    }
}
