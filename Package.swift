// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZipIt",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "ZipIt", targets: ["ZipIt"])
    ],
    dependencies: [
        // ZIP file handling
        .package(url: "https://github.com/marmelroy/Zip.git", from: "2.1.0"),
        
        // RAR and 7Z file handling through SWCompression
        .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.8.0"),
        
        // GZIP file handling
        .package(url: "https://github.com/1024jp/GzipSwift.git", from: "5.2.0"),
        
        // RAR file handling
        .package(url: "https://github.com/mtgto/Unrar.swift.git", from: "0.3.15")
    ],
    targets: [
        .executableTarget(
            name: "ZipIt",
            dependencies: [
                "Zip",
                "SWCompression",
                .product(name: "Gzip", package: "GzipSwift"),
                .product(name: "Unrar", package: "unrar.swift")
            ],
            path: "ZipIt",
            exclude: ["Assets.xcassets", "ZipIt.entitlements"],
            resources: []
        )
    ]
)
