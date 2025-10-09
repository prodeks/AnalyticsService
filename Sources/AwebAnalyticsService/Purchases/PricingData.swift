import Foundation

public class PricingData {
    public let value: Double
    public let priceLocale: Locale
    public let currencySymbol: String
    public let iap: any IAPProtocol
    
    init(
        value: Double,
        priceLocale: Locale,
        currencySymbol: String,
        iap: any IAPProtocol
    ) {
        self.value = value
        self.priceLocale = priceLocale
        self.currencySymbol = currencySymbol
        self.iap = iap
    }
    
    public lazy var localizedPrice: String = {
        let currency = priceLocale.currency?.identifier ?? ""
        let formatted = String(format: "%.2f", value)
        return "\(formatted) \(currency)"
    }()
    
    public lazy var weeklyPrice: String = {
        let currency = priceLocale.currency?.identifier ?? ""
        let weeklyPrice = value / Double(iap.weekCount)
        let formatted = String(format: "%.2f", weeklyPrice)
        return "\(formatted) \(currency)"
    }()
    
    public lazy var dailyPrice: String = {
        let currency = priceLocale.currency?.identifier ?? ""
        let dailyPrice = value / Double(iap.weekCount * 7)
        let formatted = String(format: "%.2f", dailyPrice)
        return "\(formatted) \(currency)"
    }()
    public lazy var yearlyPrice: String = {
        let currency = priceLocale.currency?.identifier ?? ""
        let yearlyPrice = (value / Double(iap.weekCount)) * 52
        let formatted = String(format: "%.2f", yearlyPrice)
        return "\(formatted) \(currency)"
    }()
}
