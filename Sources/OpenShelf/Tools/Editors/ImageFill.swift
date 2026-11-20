import CoreGraphics
import Foundation

/// Fills marked areas of an image so they blend with what is around them (ROADMAP E6,
/// the no-dependency fill): each area becomes the smoothest surface that meets the
/// pixels at its edge (a Laplace fill). Good on flat or gently changing backgrounds;
/// on detailed ones it smears. No model, no network.
enum ImageFill {
    /// `image` with each rect (image pixels, origin top-left) filled from its edges.
    static func fill(_ image: CGImage, areas: [CGRect]) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        for area in areas {
            let rect = area.integral.intersection(bounds)
            guard !rect.isNull, rect.width > 0, rect.height > 0 else { continue }
            fill(&pixels, width: width, height: height, x0: Int(rect.minX), y0: Int(rect.minY), x1: Int(rect.maxX), y1: Int(rect.maxY))
        }
        return context.makeImage()
    }

    /// The Laplace fill of the box [x0, x1) × [y0, y1) in an RGBA buffer, its edge
    /// fixed by the pixels just outside it.
    static func fill(_ pixels: inout [UInt8], width: Int, height: Int, x0: Int, y0: Int, x1: Int, y1: Int) {
        let w = x1 - x0, h = y1 - y0
        // A covered whole image has no edge to fill from.
        guard x0 > 0 || y0 > 0 || x1 < width || y1 < height else { return }
        func outside(_ x: Int, _ y: Int, _ c: Int) -> Float? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            return Float(pixels[(y * width + x) * 4 + c])
        }
        for channel in 0..<4 {
            var grid = [Float](repeating: 0, count: w * h)
            // A start between the edges, row and column, so few rounds are needed.
            for y in 0..<h {
                for x in 0..<w {
                    var total: Float = 0, weight: Float = 0
                    if let left = outside(x0 - 1, y0 + y, channel), let right = outside(x1, y0 + y, channel) {
                        let t = Float(x + 1) / Float(w + 1)
                        total += left * (1 - t) + right * t; weight += 1
                    } else if let one = outside(x0 - 1, y0 + y, channel) ?? outside(x1, y0 + y, channel) {
                        total += one; weight += 1
                    }
                    if let top = outside(x0 + x, y0 - 1, channel), let bottom = outside(x0 + x, y1, channel) {
                        let t = Float(y + 1) / Float(h + 1)
                        total += top * (1 - t) + bottom * t; weight += 1
                    } else if let one = outside(x0 + x, y0 - 1, channel) ?? outside(x0 + x, y1, channel) {
                        total += one; weight += 1
                    }
                    grid[y * w + x] = weight > 0 ? total / weight : 0
                }
            }
            // Gauss-Seidel rounds of the 4-neighbour average.
            let rounds = min(max(w, h) * 2, 400)
            for _ in 0..<rounds {
                for y in 0..<h {
                    for x in 0..<w {
                        var total: Float = 0, count: Float = 0
                        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                            let nx = x + dx, ny = y + dy
                            if nx >= 0, ny >= 0, nx < w, ny < h {
                                total += grid[ny * w + nx]; count += 1
                            } else if let value = outside(x0 + nx, y0 + ny, channel) {
                                total += value; count += 1
                            }
                        }
                        if count > 0 { grid[y * w + x] = total / count }
                    }
                }
            }
            for y in 0..<h {
                for x in 0..<w {
                    pixels[((y0 + y) * width + x0 + x) * 4 + channel] = UInt8(min(max(grid[y * w + x].rounded(), 0), 255))
                }
            }
        }
    }
}
