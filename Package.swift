// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notepad",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "NotepadKit"),
        .executableTarget(name: "Notepad", dependencies: ["NotepadKit"]),
        .testTarget(name: "NotepadKitTests", dependencies: ["NotepadKit"]),
    ]
)
