import CryptoKit
import Foundation

/// iOS 17 drops the personalized Developer Disk Image on every reboot, and the
/// location service does not exist without it. WrapPin keeps a local copy of
/// Apple's generic personalized DDI (from the community mirror used by
/// pymobiledevice3, pinned to one commit) and lets the native engine mount it.
/// The device-specific ticket is requested from Apple at mount time.
actor DeveloperDiskImageStore {
    static let shared = DeveloperDiskImageStore()

    private struct Component {
        let name: String
        let size: Int
        /// Git blob SHA-1 at the pinned commit, so a tampered or truncated
        /// download is rejected before it reaches the iPhone.
        let gitBlobSHA1: String
    }

    private static let pinnedCommit = "a1020f81b6429f5ce40408cbe21c690512b613b5"
    private static let remoteFolder = "PersonalizedImages/Xcode_iOS_DDI_Personalized"
    private static let components = [
        Component(name: "BuildManifest.plist", size: 800_656,
                  gitBlobSHA1: "ecd4f63bc38be1682b3f9f52e82cff63dfa5057f"),
        Component(name: "Image.dmg", size: 17_084_416,
                  gitBlobSHA1: "1e1f423fa6db5570fa8c00c683ce77cda14e8b99"),
        Component(name: "Image.dmg.trustcache", size: 1_851,
                  gitBlobSHA1: "5d313bf7958c3f482a556d13cf6c6f22a0012835")
    ]

    enum StoreError: LocalizedError {
        case download(String)
        case verification(String)

        var errorDescription: String? {
            switch self {
            case .download(let name):
                String(format: NSLocalizedString("Could not download %@. Check the internet connection and try again.", comment: ""), name)
            case .verification(let name):
                String(format: NSLocalizedString("The downloaded %@ did not pass verification. Try again.", comment: ""), name)
            }
        }
    }

    nonisolated var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DeveloperDiskImage", isDirectory: true)
    }

    /// True when every component is present with the expected size.
    nonisolated var isDownloaded: Bool {
        Self.components.allSatisfy { component in
            let url = directory.appendingPathComponent(component.name)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
            return size == component.size
        }
    }

    /// The directory to hand to the native engine, or nil if not downloaded.
    nonisolated var directoryIfReady: String? {
        isDownloaded ? directory.path : nil
    }

    func download(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)

        let total = Double(Self.components.reduce(0) { $0 + $1.size })
        var completed = 0.0
        for component in Self.components {
            let destination = directory.appendingPathComponent(component.name)
            if let data = try? Data(contentsOf: destination), Self.verify(data, component) {
                completed += Double(component.size)
                progress?(completed / total)
                continue
            }

            let source = URL(string: "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/\(Self.pinnedCommit)/\(Self.remoteFolder)/\(component.name)")!
            let data: Data
            do {
                let (body, response) = try await URLSession.shared.data(from: source)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw StoreError.download(component.name)
                }
                data = body
            } catch let error as StoreError {
                throw error
            } catch {
                throw StoreError.download(component.name)
            }
            guard Self.verify(data, component) else {
                throw StoreError.verification(component.name)
            }
            try data.write(to: destination, options: .atomic)
            completed += Double(component.size)
            progress?(completed / total)
        }
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private static func verify(_ data: Data, _ component: Component) -> Bool {
        guard data.count == component.size else { return false }
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(data.count)\0".utf8))
        hasher.update(data: data)
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return hex == component.gitBlobSHA1
    }
}
