import Foundation

/// Installed apps and SwiftPM builds have different resource locations.
/// Missing optional resources must not invoke Bundle.module's fatal accessor.
enum AppResources {
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                     Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        for root in roots {
            let location = root.appendingPathComponent("ScholarForge_ScholarForge.bundle")
            if let bundle = Bundle(url: location),
               let url = bundle.url(forResource: name, withExtension: ext) { return url }
        }
        return nil
    }
}
