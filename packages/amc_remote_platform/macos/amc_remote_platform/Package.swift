// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "amc_remote_platform",
  platforms: [.macOS("12.0")],
  products: [.library(name: "amc-remote-platform", targets: ["amc_remote_platform"])],
  targets: [.target(name: "amc_remote_platform")]
)
