import Foundation
import CoreGraphics

/// Detects cards in a photo by color segmentation: the playmat is a
/// uniform color, cards are not. Finding "non-playmat blobs" finds cards.
///
/// Algorithm:
/// 1. Downsample to ~400px wide (speed)
/// 2. Sample border pixels to find the dominant background (playmat) color
/// 3. Threshold: each pixel → background (0) or foreground/card (1)
/// 4. Connected components labeling to find distinct blobs
/// 5. Filter blobs by size and aspect ratio
/// 6. Crop each blob from the ORIGINAL full-resolution image
///
/// This approach is layout-independent — works for grids, triangles,
/// scattered cards, any arrangement. The only requirement is that
/// cards don't physically overlap and the playmat is a solid-ish color.
struct ColorSegmentationCardDetector: Sendable {

    /// Multiple thresholds to try (highest first). The detector runs at
    /// each threshold and picks the one that finds the most card-shaped blobs.
    /// Higher thresholds work for light cards; lower thresholds catch dark cards.
    private let thresholds: [Double] = [65.0, 50.0, 38.0]

    /// Minimum blob area as fraction of image area. Filters out noise.
    private let minBlobArea: Double = 0.02  // 2% of image

    /// Maximum blob area — rejects blobs that are the entire image.
    private let maxBlobArea: Double = 0.6

    /// Target width for the downsampled working image.
    private let workingWidth: Int = 400

    /// Card aspect ratio range (width/height).
    private let minAspect: Double = 0.4
    private let maxAspect: Double = 1.0

    /// Padding added to each blob's bounding box before cropping (fraction).
    private let cropPadding: Double = 0.03

    func detectCards(in image: CGImage) -> [CGImage] {
        let origW = image.width
        let origH = image.height
        guard origW > 50 && origH > 50 else { return [] }

        // 1. Downsample
        let scale = Double(workingWidth) / Double(origW)
        let w = workingWidth
        let h = Int(Double(origH) * scale)
        guard w > 10 && h > 10 else { return [] }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 2. Sample background color from edges (outermost 5%)
        let bg = sampleBackgroundColor(pixels: pixels, w: w, h: h)

        // 3. Precompute per-pixel distances (shared across thresholds)
        var distances = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let off = (y * w + x) * 4
                let r = Double(pixels[off])
                let g = Double(pixels[off + 1])
                let b = Double(pixels[off + 2])
                distances[y * w + x] = sqrt(
                    (r - bg.r) * (r - bg.r) +
                    (g - bg.g) * (g - bg.g) +
                    (b - bg.b) * (b - bg.b)
                )
            }
        }

        // 4. Run ALL thresholds and MERGE results. Different thresholds
        // catch different cards: high threshold catches light/colorful cards,
        // low threshold catches dark cards on dark playmats. No single
        // threshold finds all cards, so we union them with overlap dedup.
        var allRects: [CGRect] = []

        for threshold in thresholds {
            let rects = detectAtThreshold(
                threshold, distances: distances,
                w: w, h: h, origW: origW, origH: origH, bg: bg
            )
            print("[MTGScanner] Threshold \(Int(threshold)): \(rects.count) cards")
            for rect in rects {
                // Only add if it doesn't overlap significantly with existing rects
                let overlaps = allRects.contains { existing in
                    let intersection = existing.intersection(rect)
                    guard !intersection.isNull else { return false }
                    let overlapArea = intersection.width * intersection.height
                    let smallerArea = min(existing.width * existing.height, rect.width * rect.height)
                    return overlapArea / smallerArea > 0.5
                }
                if !overlaps {
                    allRects.append(rect)
                }
            }
        }

        print("[MTGScanner] Color segmentation: bg=(\(Int(bg.r)),\(Int(bg.g)),\(Int(bg.b))), merged → \(allRects.count) cards")

        // 5. Crop from original image
        return cropFromRects(allRects, image: image)
    }

    /// Detects cards and returns both cropped images AND their bounding rects
    /// in original image pixel coordinates. Used by the image splitter.
    func detectCardsWithRects(in image: CGImage) -> [(image: CGImage, rect: CGRect)] {
        let origW = image.width
        let origH = image.height
        guard origW > 50 && origH > 50 else { return [] }

        let scale = Double(workingWidth) / Double(origW)
        let w = workingWidth
        let h = Int(Double(origH) * scale)
        guard w > 10 && h > 10 else { return [] }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let bg = sampleBackgroundColor(pixels: pixels, w: w, h: h)
        var distances = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let off = (y * w + x) * 4
                let r = Double(pixels[off])
                let g = Double(pixels[off + 1])
                let b = Double(pixels[off + 2])
                distances[y * w + x] = sqrt(
                    (r - bg.r) * (r - bg.r) + (g - bg.g) * (g - bg.g) + (b - bg.b) * (b - bg.b)
                )
            }
        }

        var allRects: [CGRect] = []
        for threshold in thresholds {
            let rects = detectAtThreshold(threshold, distances: distances, w: w, h: h, origW: origW, origH: origH, bg: bg)
            for rect in rects {
                let overlaps = allRects.contains { existing in
                    let intersection = existing.intersection(rect)
                    guard !intersection.isNull else { return false }
                    let overlapArea = intersection.width * intersection.height
                    let smallerArea = min(existing.width * existing.height, rect.width * rect.height)
                    return overlapArea / smallerArea > 0.5
                }
                if !overlaps { allRects.append(rect) }
            }
        }

        return allRects.compactMap { rect in
            guard let cropped = image.cropping(to: rect) else { return nil }
            return (image: cropped, rect: rect)
        }
    }

    private func cropFromRects(_ rects: [CGRect], image: CGImage) -> [CGImage] {
        return rects.compactMap { rect in
            image.cropping(to: rect)
        }
    }

    /// Runs detection at a single threshold and returns card-shaped bounding rects.
    private func detectAtThreshold(
        _ threshold: Double,
        distances: [Double],
        w: Int, h: Int,
        origW: Int, origH: Int,
        bg: RGB
    ) -> [CGRect] {
        // Threshold → binary mask
        var mask = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            mask[i] = distances[i] > threshold ? 1 : 0
        }

        // Connected components
        let (labels, _) = connectedComponents(mask: mask, w: w, h: h)

        // Compute bounding boxes per label
        var bboxes = [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int)]()
        var areas = [Int: Int]()
        for y in 0..<h {
            for x in 0..<w {
                let label = labels[y * w + x]
                guard label > 0 else { continue }
                areas[label, default: 0] += 1
                if var bb = bboxes[label] {
                    bb.minX = min(bb.minX, x)
                    bb.minY = min(bb.minY, y)
                    bb.maxX = max(bb.maxX, x)
                    bb.maxY = max(bb.maxY, y)
                    bboxes[label] = bb
                } else {
                    bboxes[label] = (x, y, x, y)
                }
            }
        }

        // Filter by size, aspect ratio, and fill ratio
        let imageArea = Double(w * h)
        var cardRects: [CGRect] = []
        for (label, bb) in bboxes {
            let area = Double(areas[label] ?? 0)
            let areaFrac = area / imageArea
            guard areaFrac >= minBlobArea && areaFrac <= maxBlobArea else { continue }

            let bw = Double(bb.maxX - bb.minX + 1)
            let bh = Double(bb.maxY - bb.minY + 1)
            guard bh > 0 else { continue }
            let aspect = bw / bh
            guard aspect >= minAspect && aspect <= maxAspect else { continue }

            let bboxArea = bw * bh
            let fillRatio = area / bboxArea
            guard fillRatio >= 0.60 else { continue }

            let pad = cropPadding
            let ox = max(0, Double(bb.minX) / Double(w) - pad) * Double(origW)
            let oy = max(0, Double(bb.minY) / Double(h) - pad) * Double(origH)
            let ow = min(Double(origW) - ox, (bw / Double(w) + pad * 2) * Double(origW))
            let oh = min(Double(origH) - oy, (bh / Double(h) + pad * 2) * Double(origH))

            cardRects.append(CGRect(x: ox, y: oy, width: ow, height: oh))
        }

        return cardRects
    }

    // MARK: - Background color sampling

    private struct RGB { let r: Double; let g: Double; let b: Double }

    private func sampleBackgroundColor(pixels: [UInt8], w: Int, h: Int) -> RGB {
        var totalR = 0.0, totalG = 0.0, totalB = 0.0
        var count = 0.0
        let margin = max(1, min(w, h) / 20) // 5% margin

        for y in 0..<h {
            for x in 0..<w {
                // Only sample edge pixels
                guard x < margin || x >= w - margin ||
                      y < margin || y >= h - margin else { continue }
                let off = (y * w + x) * 4
                totalR += Double(pixels[off])
                totalG += Double(pixels[off + 1])
                totalB += Double(pixels[off + 2])
                count += 1
            }
        }
        guard count > 0 else { return RGB(r: 0, g: 0, b: 0) }
        return RGB(r: totalR / count, g: totalG / count, b: totalB / count)
    }

    // MARK: - Connected components (union-find)

    private func connectedComponents(mask: [UInt8], w: Int, h: Int) -> ([Int], Int) {
        var labels = [Int](repeating: 0, count: w * h)
        var parent = [Int]()
        parent.append(0) // label 0 = background
        var nextLabel = 1

        func find(_ x: Int) -> Int {
            var i = x
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        for y in 0..<h {
            for x in 0..<w {
                guard mask[y * w + x] == 1 else { continue }

                let left = x > 0 ? labels[y * w + (x - 1)] : 0
                let top = y > 0 ? labels[(y - 1) * w + x] : 0

                if left > 0 && top > 0 {
                    labels[y * w + x] = left
                    if left != top { union(left, top) }
                } else if left > 0 {
                    labels[y * w + x] = left
                } else if top > 0 {
                    labels[y * w + x] = top
                } else {
                    labels[y * w + x] = nextLabel
                    parent.append(nextLabel)
                    nextLabel += 1
                }
            }
        }

        // Flatten labels
        for i in 0..<(w * h) {
            if labels[i] > 0 {
                labels[i] = find(labels[i])
            }
        }

        return (labels, nextLabel - 1)
    }
}
