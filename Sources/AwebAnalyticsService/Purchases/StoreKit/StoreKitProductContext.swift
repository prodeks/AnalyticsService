import StoreKit

/// Product-level economics extracted from a StoreKit `Product`.
struct StoreKitProductContext {
    let productID: String
    let price: Float
    let currency: String

    init(product: StoreKit.Product) {
        self.productID = product.id
        self.price = Float(truncating: product.price as NSDecimalNumber)
        self.currency = product.priceFormatStyle.currencyCode
    }
}
