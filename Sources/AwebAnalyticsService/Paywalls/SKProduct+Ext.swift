import StoreKit

extension SKProduct {
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    var localizedPrice: String? {
        SKProduct.formatter.locale = priceLocale
        return SKProduct.formatter.string(from: price)
    }
}
