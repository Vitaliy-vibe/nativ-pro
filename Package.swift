// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PhotoEditor",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "EditorCore", targets: ["EditorCore"]),
        .library(name: "EditorRenderMetal", targets: ["EditorRenderMetal"]),
        .library(name: "EditorApp", targets: ["EditorApp"]),
        .executable(name: "pe", targets: ["pe"]),
        .executable(name: "PhotoEditor", targets: ["PhotoEditor"]),
    ],
    targets: [
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        // SQLite встроена исходником (Sources/CSQLite/VERSION.txt), чтобы поведение не зависело от системы.
        .target(
            name: "CSQLite",
            path: "Sources/CSQLite",
            exclude: ["VERSION.txt"],
            sources: ["sqlite3.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_DQS", to: "0"),
                .define("SQLITE_DEFAULT_MEMSTATUS", to: "0"),
                .define("SQLITE_OMIT_LOAD_EXTENSION"),
                .define("SQLITE_OMIT_DEPRECATED"),
                // Предупреждения чужого исходника не про наш код — не засоряем журнал сборки.
                .unsafeFlags(["-w"]),
            ]
        ),
        .target(name: "EditorCore", dependencies: ["CZlib", "CSQLite"]),
        // Рендер на Metal; на Linux модуль собирается пустым (#if canImport(Metal)).
        .target(name: "EditorRenderMetal", dependencies: ["EditorCore"]),
        // Логика окна без AppKit (меню, команды, масштаб) — проверяется тестами и на Linux.
        .target(name: "EditorApp", dependencies: ["EditorCore"]),
        .executableTarget(name: "pe", dependencies: ["EditorCore", "EditorRenderMetal"]),
        // Приложение macOS (AppKit); на Linux собирается заглушкой. Сборка .app — tools/build_app.sh.
        .executableTarget(name: "PhotoEditor", dependencies: ["EditorCore", "EditorRenderMetal", "EditorApp"],
                          // AppKit-код пока в режиме Swift 5: строгая проверка потоков — отдельной задачей.
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore"]),
        .testTarget(name: "EditorAppTests", dependencies: ["EditorCore", "EditorApp"]),
        .testTarget(name: "EditorRenderMetalTests", dependencies: ["EditorCore", "EditorRenderMetal"]),
    ]
)
