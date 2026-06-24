// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CodexAccounts",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexAccounts", targets: ["CodexAccounts"])
    ],
    targets: [
        .executableTarget(
            name: "CodexAccounts",
            path: "Sources/CodexAccounts",
            resources: [
                .copy("Resources/shim.sh")
            ]
        ),
        .testTarget(
            name: "CodexAccountsTests",
            dependencies: ["CodexAccounts"]
        )
    ]
)
