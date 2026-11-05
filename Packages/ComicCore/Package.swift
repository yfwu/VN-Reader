// swift-tools-version:6.0
import PackageDescription

// RARLAB unrar sources compiled as the library ("RARDLL") variant.
// The list mirrors OBJECTS + LIB_OBJ of unrar's own makefile; other .cpp
// files are #included by these and must not be compiled separately.
let unrarSources = [
    "rar", "strlist", "strfn", "pathfn", "smallfn", "global", "file", "filefn", "filcreat",
    "archive", "arcread", "unicode", "system", "crypt", "crc", "rawread", "encname",
    "resource", "match", "timefn", "rdwrfn", "consio", "options", "errhnd", "rarvm", "secpassword",
    "rijndael", "getbits", "sha1", "sha256", "blake2s", "hash", "extinfo", "extract", "volume",
    "list", "find", "unpack", "headers", "threadpool", "rs16", "cmddata", "ui", "largepage",
    "filestr", "scantree", "dll", "qopen",
].map { "unrar/\($0).cpp" }

let package = Package(
    name: "ComicCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "ComicCore", targets: ["ComicCore"]),
    ],
    targets: [
        .target(
            name: "CUnrar",
            path: "Sources/CUnrar",
            exclude: ["unrar/license.txt", "unrar/readme.txt", "unrar/acknow.txt", "unrar/makefile",
                      "unrar/dll.def", "unrar/dll_nocrypt.def"],
            sources: unrarSources + ["vnrar.cpp"],
            publicHeadersPath: "include",
            cxxSettings: [
                .define("RARDLL"),
                .define("_FILE_OFFSET_BITS", to: "64"),
                .define("_LARGEFILE_SOURCE"),
                .define("RAR_SMP"),
                .headerSearchPath("unrar"),
                // Vendored upstream code is kept unmodified; silence its style warnings
                // (same intent as the -Wno-* flags in unrar's own makefile). Allowed
                // because this package is only ever used as a local/root package.
                .unsafeFlags(["-w"]),
            ],
            linkerSettings: [.linkedLibrary("pthread", .when(platforms: [.linux]))]
        ),
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(
            name: "ComicCore",
            dependencies: ["CUnrar", "CZlib"]
        ),
        .testTarget(
            name: "ComicCoreTests",
            dependencies: ["ComicCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx11
)
