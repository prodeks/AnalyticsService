// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AwebAnalyticsService",
    platforms: [.iOS(.v15)],
    products: [.library(name: "AwebAnalyticsService", targets: ["AwebAnalyticsService"])],
    dependencies: [
        .package(url: "https://github.com/BranchMetrics/ios-branch-sdk-spm", exact: Version(3, 4, 3)),
        .package(url: "https://github.com/facebook/facebook-ios-sdk", exact: Version(17, 0, 2)),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", exact: Version(10, 27, 0)),
        .package(url: "https://github.com/ASATools/ios_sdk.git", exact: Version(1, 4, 7)),
        .package(url: "https://github.com/airbnb/lottie-ios.git", exact: Version(4, 4, 3)),
        .package(url: "https://github.com/bizz84/SwiftyStoreKit.git", exact: Version(0, 16, 4)),
        .package(url: "https://github.com/adaptyteam/AdaptySDK-iOS.git", exact: Version(2, 11, 0)),
    ],
    targets: [
        .target(
            name: "AwebAnalyticsService",
            dependencies: [
                .product(name: "FacebookCore", package: "facebook-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "BranchSDK", package: "ios-branch-sdk-spm"),
                .product(name: "ASATools", package: "ios_sdk"),
                .product(name: "Lottie", package: "lottie-ios"),
                .product(name: "SwiftyStoreKit", package: "SwiftyStoreKit"),
                .product(name: "Adapty", package: "AdaptySDK-iOS")
            ]
        )
    ]
)
