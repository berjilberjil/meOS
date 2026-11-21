// swift-tools-version: 5.9
import PackageDescription

// The finance domain is pure Swift so its arithmetic can be tested without
// booting the app or a database. The app target compiles exactly the same
// source files; this package adds no second implementation.
let package = Package(
    name: "MeOSFinanceCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "FinanceCore",
            path: "MeOS/Core/Finance",
            exclude: ["FinanceStore.swift"]
        ),
        .testTarget(
            name: "FinanceCoreTests",
            dependencies: ["FinanceCore"],
            path: "Tests/FinanceCoreTests"
        )
    ]
)
