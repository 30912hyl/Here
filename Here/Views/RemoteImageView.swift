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

enum RemoteImagePhase {
    case loading
    case success(Image)
    case failure
}

/// Drop-in replacement for AsyncImage that decodes downsampled.
/// Downloads go through URLSession.shared, so responses are URLCache-backed.
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
    }

    private func load() async {
        guard let url else {
            phase = .failure
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage.downsampled(data: data, maxPixelSize: maxPixelSize) {
                phase = .success(Image(uiImage: image))
            } else {
                phase = .failure
            }
        } catch {
            if !Task.isCancelled {
                phase = .failure
            }
        }
    }
}
