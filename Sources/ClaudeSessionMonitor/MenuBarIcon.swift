import AppKit

/// Dibuja el icono de la barra de menús: el logo de Claude relleno de abajo arriba según el uso semanal
/// (la parte sin usar queda translúcida) y, opcionalmente, un texto.
/// Es una imagen plantilla, así que macOS la pinta en blanco o negro según la barra.
enum MenuBarIcon {
    private struct Logo {
        let image: NSImage
        /// Franja vertical que ocupa el dibujo dentro de la imagen (0 = abajo, 1 = arriba), para que
        /// el 50 % llene medio logo y no media imagen con márgenes.
        let glyphBottom: CGFloat
        let glyphTop: CGFloat
    }

    private static let logo: Logo = loadLogo()
    private static let emptyAlpha: CGFloat = 0.3

    /// `weeklyPercent` nil = sin datos (logo translúcido entero).
    static func image(weeklyPercent: Double?, text: String?) -> NSImage {
        let iconSize: CGFloat = 18
        let height: CGFloat = 18
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attributed = text.map { NSAttributedString(string: $0, attributes: [.font: font, .foregroundColor: NSColor.black]) }
        let textWidth = attributed.map { ceil($0.size().width) + 4 } ?? 0
        let size = NSSize(width: iconSize + textWidth, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            let iconRect = NSRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize)
            logo.image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: emptyAlpha)

            if let weeklyPercent, weeklyPercent > 0 {
                let glyphMinY = iconRect.minY + iconRect.height * logo.glyphBottom
                let glyphHeight = iconRect.height * (logo.glyphTop - logo.glyphBottom)
                let level = glyphMinY + glyphHeight * min(weeklyPercent, 100) / 100
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: iconRect.minX, y: iconRect.minY, width: iconRect.width, height: level - iconRect.minY)).addClip()
                logo.image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            }

            if let attributed {
                let textSize = attributed.size()
                attributed.draw(at: NSPoint(x: iconSize + 4, y: (height - textSize.height) / 2))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Logo

    /// Usa la silueta oficial que trae la app de escritorio de Claude; si no está instalada, dibuja un destello parecido.
    private static func loadLogo() -> Logo {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop")
            ?? URL(fileURLWithPath: "/Applications/Claude.app")
        let image = NSImage(contentsOf: appURL.appending(path: "Contents/Resources/TrayIconTemplate@3x.png"))
            ?? fallbackSpark()
        let (bottom, top) = verticalGlyphBounds(of: image)
        return Logo(image: image, glyphBottom: bottom, glyphTop: top)
    }

    private static func fallbackSpark() -> NSImage {
        NSImage(size: NSSize(width: 72, height: 72), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let lengths: [CGFloat] = [1, 0.8, 0.95, 0.75, 1, 0.85, 0.9, 0.78, 1, 0.82, 0.92, 0.76]
            NSColor.black.setStroke()
            for (index, length) in lengths.enumerated() {
                let angle = CGFloat(index) * .pi / 6 + 0.12
                let radius = rect.width * 0.44 * length
                let ray = NSBezierPath()
                ray.move(to: center)
                ray.line(to: NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                ray.lineWidth = rect.width * 0.09
                ray.lineCapStyle = .round
                ray.stroke()
            }
            return true
        }
    }

    private static func verticalGlyphBounds(of image: NSImage) -> (bottom: CGFloat, top: CGFloat) {
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsHigh > 0 else {
            return (0, 1)
        }
        var firstRow: Int?
        var lastRow = 0
        for row in 0..<bitmap.pixelsHigh {
            for column in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: column, y: row)?.alphaComponent ?? 0) > 0.1 {
                if firstRow == nil { firstRow = row }
                lastRow = row
                break
            }
        }
        guard let firstRow else { return (0, 1) }
        // Las filas del bitmap van de arriba abajo.
        let height = CGFloat(bitmap.pixelsHigh)
        return (1 - CGFloat(lastRow + 1) / height, 1 - CGFloat(firstRow) / height)
    }
}
