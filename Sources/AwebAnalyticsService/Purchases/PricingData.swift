import Foundation

public struct PricingData {
    public let value: Double
    public let localizedPrice: String
    public let priceLocale: Locale
    public let currencySymbol: String
    public let iap: any IAPProtocol
    
    public lazy var priceLocaleAndValue: (locale: Locale, value: Double)? = parsePrice(from: localizedPrice)
    
    public lazy var weeklyPrice: String? = priceLocaleAndValue
        .map { arg in
            return localizedWeeklyPrice((iap: iap, price: arg))
        }
    public lazy var dailyPrice: String? = priceLocaleAndValue
        .map { arg in
            return localizedDailyPrice((iap: iap, price: arg))
        }
    public lazy var yearlyPrice: String? = priceLocaleAndValue
        .map { arg in
            return localizedYearlyPrice((iap: iap, price: arg))
        }
}

fileprivate let f = NumberFormatter()

func parsePrice(from priceString: String) -> (locale: Locale, value: Double)? {
    for identifier in Locale.availableIdentifiers {
        let locale = Locale(identifier: identifier)
        
        f.locale = locale
        f.numberStyle = .currency

        if let number = f.number(from: priceString) {
            if let currencySymbol = locale.currencySymbol, priceString.contains(currencySymbol) {
                return (locale, number.doubleValue)
            }
        }
    }
    return nil
}

func localizedWeeklyPrice(_ arg: (iap: any IAPProtocol, price: (locale: Locale, value: Double))) -> String {
    f.locale = arg.price.locale
    f.numberStyle = .currency
    let weeklyPrice = arg.price.value / Double(arg.iap.weekCount)
    return f.string(from: NSNumber(value: weeklyPrice)) ?? ""
}

func localizedDailyPrice(_ arg: (iap: any IAPProtocol, price: (locale: Locale, value: Double))) -> String {
    f.locale = arg.price.locale
    f.numberStyle = .currency
    let dailyPrice = arg.price.value / Double(arg.iap.weekCount * 7)
    return f.string(from: NSNumber(value: dailyPrice)) ?? ""
}

func localizedYearlyPrice(_ arg: (iap: any IAPProtocol, price: (locale: Locale, value: Double))) -> String {
    f.locale = arg.price.locale
    f.numberStyle = .currency
    let yearlyPrice = (arg.price.value / Double(arg.iap.weekCount)) * 52
    return f.string(from: NSNumber(value: yearlyPrice)) ?? ""
}

func localizedMonthlyPrice(_ arg: (iap: any IAPProtocol, price: (locale: Locale, value: Double))) -> String {
    f.locale = arg.price.locale
    f.numberStyle = .currency
    let monthlyPrice = (arg.price.value / Double(arg.iap.weekCount)) * 4.33
    return f.string(from: NSNumber(value: monthlyPrice)) ?? ""
}
