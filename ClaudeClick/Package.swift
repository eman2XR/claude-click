// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutomationTool",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "claude-click",
            targets: ["AutomationTool"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AutomationTool",
            path: "Sources/AutomationTool",
            resources: [
                .process("Resources/clip-vocab.json"),
                .process("Resources/clip-merges.txt"),
                .copy("Resources/mobileclip_s0_text.mlpackage")
            ]
        )
    ]
)
