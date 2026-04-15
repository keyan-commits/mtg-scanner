import Foundation
import CoreGraphics
import Vision

/// Detects multiple MTG cards in a photo by clustering OCR text
/// regions spatially. Instead of finding card-shaped rectangles
/// (which also finds playmat logos, art frames, and text boxes),
/// this approach:
///
/// 1. Runs OCR on the full image to find all text observations
/// 2. Dilates each text bounding box slightly
/// 3. Groups overlapping dilated boxes into clusters (union-find)
/// 4. Each cluster with ≥3 text regions is a card
/// 5. Computes the cluster bounding box expanded to card aspect ratio
/// 6. Crops that region from the original image
///
/// This is more reliable than rectangle detection because:
/// - Playmat logos have 0-1 text regions → filtered out
/// - Art frames inside cards merge with the card's own text cluster
/// - Works for any card layout (grid, scattered, angled)
/// - The only tunable parameter is the dilation factor
struct TextClusterCardDetector: Sendable {

    /// Minimum text observations in a cluster to be considered a card.
    /// Real cards have 5+ (name, type, rules, P/T, artist, copyright).
    /// Set to 2 because old-frame cards and basic lands in `.fast` OCR
    /// mode may only produce 2 observations (title + one other line).
    /// The identification pipeline handles false positives from small
    /// clusters — a 2-text cluster that isn't a card simply won't
    /// match any name in the DB.
    private let minClusterSize = 2

    /// Small X-dilation for final box expansion. The main clustering
    /// logic uses horizontal-overlap instead of dilation (see below).
    private let dilationX: CGFloat = 0.015

    /// MTG card aspect ratio (width / height).
    private let cardAspect: CGFloat = 63.0 / 88.0

    /// Finds card regions in an image via text clustering.
    /// Returns cropped images ready for `identifyCropped()`.
    func detectCards(in image: CGImage) async -> [CGImage] {
        // 1. Full-image OCR — get all text observations with bounding boxes
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast  // Fast mode for detection (not reading)
        request.minimumTextHeight = 0.008
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results, observations.count >= minClusterSize else {
            return []
        }

        // 2. Collect bounding boxes (Vision normalized coords: 0-1)
        let boxes: [CGRect] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first,
                  candidate.confidence >= 0.3 else { return nil }
            return obs.boundingBox
        }
        guard boxes.count >= minClusterSize else { return [] }

        // 3. Cluster by dilated overlap (union-find)
        let clusters = clusterBoxes(boxes)

        // 4. Filter to clusters with enough text regions
        let validClusters = clusters.filter { $0.count >= minClusterSize }

        // 5. Compute bounding rect for each cluster, expand to card aspect ratio
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        var cardImages: [CGImage] = []
        for cluster in validClusters {
            let clusterBoxes = cluster.map { boxes[$0] }
            var unionRect = clusterBoxes[0]
            for box in clusterBoxes.dropFirst() {
                unionRect = unionRect.union(box)
            }

            // Expand to card aspect ratio with padding
            let expanded = expandToCardAspect(unionRect, padding: 0.02)

            // Convert from Vision coords (y=0 at bottom) to pixel coords (y=0 at top)
            let pixelRect = CGRect(
                x: expanded.minX * imageWidth,
                y: (1.0 - expanded.maxY) * imageHeight,
                width: expanded.width * imageWidth,
                height: expanded.height * imageHeight
            ).intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

            guard pixelRect.width > 50 && pixelRect.height > 50,
                  let cropped = image.cropping(to: pixelRect) else { continue }
            cardImages.append(cropped)
        }

        print("[MTGScanner] Text clustering: \(boxes.count) text regions → \(clusters.count) clusters → \(validClusters.count) cards (\(cardImages.count) cropped)")
        return cardImages
    }

    // MARK: - Horizontal-overlap clustering

    /// Clusters text boxes by horizontal overlap — text that shares
    /// the same X range belongs to the same card, regardless of the
    /// Y (vertical) distance between them. This bridges the art gap
    /// (title at top, body text below art) while keeping horizontally
    /// adjacent cards separate.
    ///
    /// Two boxes are considered "on the same card" if their X ranges
    /// overlap by at least 30% of the narrower box's width. This is
    /// much more robust than uniform dilation because:
    /// - Vertical gaps (art) don't break the cluster
    /// - Horizontal gaps (card spacing) do break the cluster
    private func clusterBoxes(_ boxes: [CGRect]) -> [[Int]] {
        var parent = Array(0..<boxes.count)

        func find(_ i: Int) -> Int {
            var x = i
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        for i in 0..<boxes.count {
            for j in (i + 1)..<boxes.count {
                if shouldCluster(boxes[i], boxes[j]) {
                    union(i, j)
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for i in 0..<boxes.count {
            groups[find(i), default: []].append(i)
        }
        return Array(groups.values)
    }

    /// Two text boxes belong to the same card if:
    /// 1. They share significant horizontal overlap (≥50% of the
    ///    narrower box) — text on the same card is vertically aligned
    /// 2. Their vertical gap is ≤ 35% of image height — bridges the
    ///    art gap within a card (~20%) but doesn't bridge between
    ///    rows of cards (~50%)
    ///
    /// This combined check handles both:
    /// - Title vs body text on the same card (different Y, same X) ✓
    /// - Cards in different rows (different Y, overlapping X) ✗
    private func shouldCluster(_ a: CGRect, _ b: CGRect) -> Bool {
        // Horizontal overlap check
        let overlapX = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        guard overlapX > 0 else { return false }
        let minWidth = min(a.width, b.width)
        guard minWidth > 0 else { return false }
        let hOverlapRatio = overlapX / minWidth
        guard hOverlapRatio >= 0.5 else { return false }

        // Vertical gap check — gap between the closest edges
        let verticalGap: CGFloat
        if a.maxY < b.minY {
            verticalGap = b.minY - a.maxY
        } else if b.maxY < a.minY {
            verticalGap = a.minY - b.maxY
        } else {
            verticalGap = 0 // overlapping vertically
        }

        // 35% of image height bridges art gap (~20%) with margin,
        // but not the gap between top row and bottom row (~50%)
        return verticalGap <= 0.35
    }

    // MARK: - Aspect ratio expansion

    /// Expands a bounding rect to the card aspect ratio (0.716),
    /// adding `padding` on each side (fraction of image).
    private func expandToCardAspect(_ rect: CGRect, padding: CGFloat) -> CGRect {
        var r = rect.insetBy(dx: -padding, dy: -padding)

        // Expand the smaller dimension to match card aspect ratio
        let currentAspect = r.width / r.height
        if currentAspect < cardAspect {
            // Too tall — expand width
            let newWidth = r.height * cardAspect
            let dx = (newWidth - r.width) / 2
            r = r.insetBy(dx: -dx, dy: 0)
        } else {
            // Too wide — expand height
            let newHeight = r.width / cardAspect
            let dy = (newHeight - r.height) / 2
            r = r.insetBy(dx: 0, dy: -dy)
        }

        // Clamp to [0, 1]
        return CGRect(
            x: max(0, r.minX),
            y: max(0, r.minY),
            width: min(1 - max(0, r.minX), r.width),
            height: min(1 - max(0, r.minY), r.height)
        )
    }
}
