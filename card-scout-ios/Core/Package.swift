// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CardScoutCore", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "CardScoutCore", targets: ["CardScoutCore"])], targets: [.target(name: "CardScoutCore"), .testTarget(name: "CardScoutCoreTests", dependencies: ["CardScoutCore"])])

