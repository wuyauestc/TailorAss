// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NativeClothCollision",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "NativeClothCollision", type: .static, targets: ["NativeClothCollision"])],
    targets: [
        .target(
            name: "CNativeClothCollision",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("vendor/eigen"),
                .headerSearchPath("vendor/spdlog"),
                .define("FMT_HEADER_ONLY"),
                .define("EIGEN_MPL2_ONLY")
            ]
        ),
        .target(
            name: "CIPCBodyContact",
            exclude: ["licenses"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("official"),
                .headerSearchPath("vendor/eigen"),
                .headerSearchPath("vendor/spdlog"),
                .define("FMT_HEADER_ONLY"),
                .define("EIGEN_MPL2_ONLY"),
                .unsafeFlags(["-fno-fast-math", "-ffp-contract=off"])
            ]
        ),
        .target(
            name: "CNativeClothSparse",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("Accelerate")]
        ),
        .target(name: "NativeClothCollision", dependencies: ["CNativeClothCollision", "CIPCBodyContact", "CNativeClothSparse"]),
        .testTarget(
            name: "NativeClothCollisionTests",
            dependencies: ["NativeClothCollision", "CNativeClothCollision", "CIPCBodyContact", "CNativeClothSparse"],
            resources: [.copy("Fixtures")]
        )
    ],
    cxxLanguageStandard: .cxx17
)

