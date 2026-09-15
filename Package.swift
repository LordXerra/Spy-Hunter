// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpyHunter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SpyHunter",
            path: "Sources/SpyHunter",
            resources: [
                .copy("Resources/spritesheet.png"),
                .copy("Resources/font.png"),
                .copy("Resources/title.jpg"),
                .copy("Resources/Music.mp3"),
                .copy("Resources/TitleMusic.mp3"),
            ],
            swiftSettings: [
                // Game code is single-threaded on the main run loop; Swift 5
                // mode keeps SpriteKit/AppKit interop free of actor ceremony.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
