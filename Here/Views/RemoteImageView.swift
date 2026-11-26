import SwiftUI
import ImageIO

// MARK: - Memory-safe image loading
//
// AsyncImage decodes photos at full resolution — a 12MP phone photo becomes
// ~46MB of RAM once decoded, and a feed of them gets the app jetsam-killed.
// These helpers decode via ImageIO thumbnailing, which never materializes the
// full-size bitmap.

extension UIImage {
    /// Decodes `data` downsampled so the longest side is at most `maxPixelSize`.
    static func downsampled(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Transient network errors used to stick as `.failure` for the life of
/// the view (issue #2: "post A without image, post B with image"). Retry a
/// few times with backoff before giving up.
/// (File-level because generic types can't hold static stored properties.)
private let remoteImageMaxAttempts = 3

enum RemoteImagePhase {
    case loading
    case success(Image)
    case failure
}

/// Downloaded image bytes (compressed, a few hundred KB each), so an image that scrolled away can
/// come back without a network trip. NSCache drops entries by itself when memory runs low.
private let remoteImageDataCache: NSCache<NSURL, NSData> = {
    let cache = NSCache<NSURL, NSData>()
    cache.totalCostLimit = 60 * 1024 * 1024
    return cache
}()

/// Drop-in replacement for AsyncImage that decodes downsampled.
/// The decoded bitmap is released when the view leaves the screen (the feed is a lazy stack that
/// keeps every page it has created, so without this every photo scrolled past stayed in memory)
/// and rebuilt from the byte cache when it comes back.
struct RemoteImageView<Content: View>: View {
    let url: URL?
    let maxPixelSize: CGFloat
    @ViewBuilder let content: (RemoteImagePhase) -> Content

    @State private var phase: RemoteImagePhase = .loading

    var body: some View {
        content(phase)
            .task(id: url) {
                await load()
            }
            .onDisappear {
                phase = .loading
            }
    }

    private func load() async {
        guard let url else {
            phase = .failure
            return
        }
        if let cached = remoteImageDataCache.object(forKey: url as NSURL) {
            if let image = UIImage.downsampled(data: cached as Data, maxPixelSize: maxPixelSize) {
                phase = .success(Image(uiImage: image))
                return
            }
        }
        for attempt in 1...remoteImageMaxAttempts {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                remoteImageDataCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
                if let image = UIImage.downsampled(data: data, maxPixelSize: maxPixelSize) {
                    phase = .success(Image(uiImage: image))
                } else {
                    phase = .failure   // bad bytes — retrying won't help
                }
                return
            } catch {
                if Task.isCancelled { return }
                if attempt < remoteImageMaxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 800_000_000)
                    if Task.isCancelled { return }
                }
            }
        }
        phase = .failure
    }
}
