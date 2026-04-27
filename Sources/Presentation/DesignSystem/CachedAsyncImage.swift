import SwiftUI

/// A drop-in replacement for AsyncImage that caches downloaded images
/// in a two-layer cache (memory + disk via URLCache).
///
/// Unlike AsyncImage which re-downloads on every view re-render,
/// CachedAsyncImage serves cached images instantly on subsequent loads.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url, image == nil else { return }
            isLoading = true
            image = await ImageCacheService.shared.image(for: url)
            isLoading = false
        }
    }
}

// MARK: - Convenience init matching AsyncImage(url:) { phase in } pattern

extension CachedAsyncImage where Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
    init(url: URL?) {
        self.url = url
        self.content = { $0 }
        self.placeholder = { ProgressView() }
    }
}

// MARK: - Phase-based convenience (matches AsyncImage API)

/// Phase-based CachedAsyncImage for easy migration from AsyncImage.
struct CachedPhaseImage<Content: View>: View {
    let url: URL?
    let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else {
                    phase = .empty
                    return
                }
                // Check cache first — instant return
                if let cached = await ImageCacheService.shared.image(for: url) {
                    phase = .success(Image(uiImage: cached))
                } else {
                    phase = .empty
                }
            }
    }
}

// MARK: - Image Cache Service

/// Two-layer image cache: in-memory NSCache + on-disk URLCache.
/// Designed for card images where the same URLs are accessed repeatedly.
actor ImageCacheService {
    static let shared = ImageCacheService()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        // Configure URLSession with aggressive disk caching
        let config = URLSessionConfiguration.default
        // 200MB disk cache, 100MB memory cache
        config.urlCache = URLCache(
            memoryCapacity: 100 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
        // NSCache holds ~500 images in memory (auto-evicts under pressure)
        memoryCache.countLimit = 500
    }

    /// Returns a cached image or downloads and caches it.
    func image(for url: URL) async -> UIImage? {
        let nsURL = url as NSURL

        // Layer 1: Memory cache (instant)
        if let cached = memoryCache.object(forKey: nsURL) {
            return cached
        }

        // Layer 2: Disk cache + network (URLSession handles this)
        do {
            let (data, _) = try await session.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            memoryCache.setObject(image, forKey: nsURL)
            return image
        } catch {
            return nil
        }
    }

    /// Prefetch images for upcoming scroll content.
    func prefetch(urls: [URL]) {
        for url in urls {
            let nsURL = url as NSURL
            guard memoryCache.object(forKey: nsURL) == nil else { continue }
            Task {
                let _ = await image(for: url)
            }
        }
    }
}
