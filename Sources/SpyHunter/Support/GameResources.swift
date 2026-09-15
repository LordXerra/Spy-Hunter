import Foundation

/// Locates the game's asset bundle.
///
/// This deliberately replaces SwiftPM's generated `Bundle.module`. That accessor
/// looks for the resource bundle beside `Bundle.main.bundleURL` — which for a
/// macOS `.app` is the bundle *root*, not `Contents/Resources` where resources
/// actually belong. When it misses, it falls back to a build path baked in at
/// compile time:
///
///     /Users/<you>/Documents/.../.build/.../SpyHunter_SpyHunter.bundle
///
/// The installed app therefore loaded its sprites, font, artwork and music from
/// the project folder rather than from inside itself. That made every launch
/// trip macOS's Documents-access prompt, and meant the `.app` was not actually
/// self-contained: move it to another Mac, or delete `.build`, and it would die
/// on the `fatalError` in that generated accessor.
///
/// We search the standard locations instead and never reference a build path.
enum GameResources {

    private static let bundleName = "SpyHunter_SpyHunter.bundle"

    static let bundle: Bundle = {
        var candidates: [URL] = []
        // Installed .app — the correct home for bundled resources.
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(bundleName))
        }
        // `swift run`, where the executable sits beside its resource bundle.
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(bundleName))
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executable.appendingPathComponent(bundleName))
        }

        for url in candidates {
            if let found = Bundle(url: url) { return found }
        }
        // Resources copied flat into the main bundle.
        if Bundle.main.url(forResource: "spritesheet", withExtension: "png") != nil {
            return Bundle.main
        }
        fatalError("""
            Could not find \(bundleName). Looked in:
            \(candidates.map(\.path).joined(separator: "\n"))
            """)
    }()

    /// URL for a bundled asset.
    static func url(_ name: String, _ ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }
}
