// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AwebAnalyticsService",
    platforms: [.iOS(.v15)],
    products: [.library(name: "AwebAnalyticsService", targets: ["AwebAnalyticsService"])],
    dependencies: [
        .package(url: "https://github.com/AppsFlyerSDK/AppsFlyerFramework-Dynamic", exact: .init(6, 15, 2)),
        .package(url: "https://github.com/facebook/facebook-ios-sdk", exact: Version(18, 0, 0)),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", exact: Version(11, 11, 0)),
        .package(url: "https://github.com/ASATools/ios_sdk.git", exact: Version(1, 5, 0)),
        .package(url: "https://github.com/airbnb/lottie-ios.git", exact: Version(4, 5, 1)),
        .package(url: "https://github.com/adaptyteam/AdaptySDK-iOS.git", exact: Version(3, 1, 0)),
        .package(url: "https://github.com/AppsFlyerSDK/PurchaseConnector-Dynamic", exact: .init(6, 15, 3))
    ],
    targets: [
        .target(
            name: "AwebAnalyticsService",
            dependencies: [
                .product(name: "FacebookCore", package: "facebook-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
                .product(name: "AppsFlyerLib-Dynamic", package: "AppsFlyerFramework-Dynamic"),
                .product(name: "ASATools", package: "ios_sdk"),
                .product(name: "Lottie", package: "lottie-ios"),
                .product(name: "Adapty", package: "AdaptySDK-iOS"),
                .product(name: "AdaptyUI", package: "AdaptySDK-iOS"),
                .product(name: "PurchaseConnector-Dynamic", package: "PurchaseConnector-Dynamic"),
            ]
        )
    ]
)
