// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AwebAnalyticsService",
    platforms: [.iOS(.v15)],
    products: [.library(name: "AwebAnalyticsService", targets: ["AwebAnalyticsService"])],
    dependencies: [
        .package(url: "https://github.com/BranchMetrics/ios-branch-sdk-spm", exact: Version(3, 3, 0)),
        .package(url: "https://github.com/facebook/facebook-ios-sdk", exact: Version(16, 3, 1)),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", exact: Version(10, 19, 0)),
        .package(url: "https://github.com/apphud/ApphudSDK.git", exact: Version(3, 2, 8)),
        .package(url: "https://github.com/ASATools/ios_sdk.git", exact: Version(1, 4, 6)),
        .package(url: "https://github.com/airbnb/lottie-ios.git", exact: Version(4, 4, 1))
    ],
    targets: [
        .target(
            name: "AwebAnalyticsService",
            dependencies: [
                .byName(name: "ApphudSDK"),
                .product(name: "FacebookCore", package: "facebook-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "BranchSDK", package: "ios-branch-sdk-spm"),
                .product(name: "ASATools", package: "ios_sdk"),
                .product(name: "Lottie", package: "lottie-ios")
            ]
        )
    ]
)
