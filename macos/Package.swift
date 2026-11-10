// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScholarForge",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "ScholarForge", targets: ["ScholarForge"])],
    targets: [.executableTarget(name: "ScholarForge", resources: [.process("Resources/seed-thesis.json"), .copy("Resources/Showcase")])]
)
