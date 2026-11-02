// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "EmojiMatchCore", platforms: [.iOS(.v16)], products: [.library(name: "EmojiMatchCore", targets: ["EmojiMatchCore"])], targets: [.target(name: "EmojiMatchCore"), .testTarget(name: "EmojiMatchCoreTests", dependencies: ["EmojiMatchCore"])])
