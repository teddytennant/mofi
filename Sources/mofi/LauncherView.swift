import AppKit

struct Layout {
    var input = NSRect.zero
    var message: NSRect?
    var rows: [NSRect] = []
    var height: CGFloat = 0
}

/// Draws everything by hand: one view, no table views, so a redraw is a
/// handful of string draws.
final class LauncherView: NSView {
    weak var launcher: Launcher!
    private var tracking: NSTrackingArea?
    private var icons: [String: NSImage] = [:]

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var theme: Theme { launcher.theme }
    private var session: Session? { launcher.session }

    override func updateTrackingAreas() {
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
        super.updateTrackingAreas()
    }

    override func keyDown(with event: NSEvent) { launcher.key(event) }
    override func mouseMoved(with event: NSEvent) { launcher.hover(row(at: event)) }
    override func mouseDown(with event: NSEvent) { launcher.click(row(at: event), count: event.clickCount) }
    override func scrollWheel(with event: NSEvent) {
        launcher.scrollWheel(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12)
    }

    private func row(at event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        return layout(width: bounds.width, rowsShown: visibleRows).rows.firstIndex { $0.contains(p) }
    }

    private var visibleRows: Int {
        guard let s = session else { return 0 }
        return theme.fixedHeight ? launcher.rows : min(launcher.rows, s.filtered.count)
    }

    private var rowHeight: CGFloat {
        let t = theme
        let iconH = (t.showIcons && (session?.hasIcons ?? false)) ? t.iconSize : 0
        return max(t.lineHeight, iconH) + t.elemPad.v * 2
    }

    func layout(width: CGFloat, rowsShown: Int) -> Layout {
        let t = theme
        var l = Layout()
        let inner = width - t.padding * 2
        var y = t.padding
        let inputH = t.lineHeight + t.inputPad.v * 2
        l.input = NSRect(x: t.padding, y: y, width: inner, height: inputH)
        y += inputH
        if let msg = session?.message, !msg.isEmpty {
            y += t.inputMargin
            let bound = (msg as NSString).boundingRect(with: NSSize(width: inner - 20, height: 10_000),
                                                       options: [.usesLineFragmentOrigin], attributes: [.font: t.font])
            let h = ceil(bound.height) + 20
            l.message = NSRect(x: t.padding, y: y, width: inner, height: h)
            y += h
        }
        if rowsShown > 0 {
            y += t.inputMargin
            let rh = rowHeight
            for i in 0..<rowsShown {
                l.rows.append(NSRect(x: t.padding, y: y, width: inner, height: rh))
                y += rh + (i < rowsShown - 1 ? t.rowSpacing : 0)
            }
        }
        l.height = ceil(y + t.padding)
        return l
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let s = session else { return }
        let t = theme
        let c = t.colors
        let l = layout(width: bounds.width, rowsShown: visibleRows)

        let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: t.border / 2, dy: t.border / 2), xRadius: t.radius, yRadius: t.radius)
        c.background.setFill()
        outer.fill()
        if t.border > 0 {
            c.border.setStroke()
            outer.lineWidth = t.border
            outer.stroke()
        }

        drawInput(s, l.input)

        if let m = l.message, let msg = s.message {
            fill(m, radius: t.inputRadius, c.messageBackground)
            let color = s.messageIsError ? c.error : c.message
            (msg as NSString).draw(with: m.insetBy(dx: 10, dy: 10), options: [.usesLineFragmentOrigin],
                                   attributes: [.font: t.font, .foregroundColor: color])
        }

        for (i, r) in l.rows.enumerated() {
            let fi = s.scroll + i
            guard fi < s.filtered.count else { break }
            drawRow(s.entries[s.filtered[fi]], r, selected: fi == s.selected, s)
        }
    }

    private func drawInput(_ s: Session, _ r: NSRect) {
        let t = theme
        let c = t.colors
        fill(r, radius: t.inputRadius, c.inputBackground)
        let lh = t.lineHeight
        let ty = r.minY + t.inputPad.v
        var x = r.minX + t.inputPad.h
        var right = r.maxX - t.inputPad.h

        if !s.prompt.isEmpty {
            let p = NSAttributedString(string: s.prompt, attributes: [.font: t.font, .foregroundColor: c.prompt])
            p.draw(at: NSPoint(x: x, y: ty))
            x += ceil(p.size().width) + t.promptGap
        }

        if t.showModes && s.modes.count > 1 {
            for (i, m) in s.modes.enumerated().reversed() {
                let a = NSAttributedString(string: m.prompt, attributes: [
                    .font: i == s.current ? t.boldFont : t.font,
                    .foregroundColor: i == s.current ? c.prompt : c.placeholder,
                ])
                let w = ceil(a.size().width)
                a.draw(at: NSPoint(x: right - w, y: ty))
                right -= w + 12
            }
        }

        let field = NSRect(x: x, y: ty, width: max(0, right - x), height: lh)
        let q = s.password ? String(repeating: "•", count: s.query.count) : s.queryString
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: field.insetBy(dx: -2, dy: 0)).addClip()
        let before = s.password ? String(repeating: "•", count: s.cursor) : String(s.query[0..<s.cursor])
        let caretX = ceil(NSAttributedString(string: before, attributes: [.font: t.font]).size().width)
        let shift = max(0, caretX - field.width + 2)
        if q.isEmpty {
            NSAttributedString(string: t.placeholder, attributes: [.font: t.font, .foregroundColor: c.placeholder])
                .draw(at: NSPoint(x: field.minX + 4, y: ty))
        } else {
            NSAttributedString(string: q, attributes: [.font: t.font, .foregroundColor: c.foreground])
                .draw(at: NSPoint(x: field.minX - shift, y: ty))
        }
        c.caret.setFill()
        NSRect(x: field.minX + caretX - shift, y: ty + 1, width: 2, height: lh - 2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawRow(_ e: Entry, _ r: NSRect, selected: Bool, _ s: Session) {
        let t = theme
        let c = t.colors
        if selected {
            NSGraphicsContext.saveGraphicsState()
            let path = NSBezierPath(roundedRect: r, xRadius: t.elemRadius, yRadius: t.elemRadius)
            path.addClip()
            c.selectedBackground.setFill()
            r.fill()
            if t.selectedBorder > 0 {
                c.selectedBorder.setFill()
                NSRect(x: r.minX, y: r.minY, width: t.selectedBorder, height: r.height).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        var x = r.minX + t.elemPad.h
        if t.showIcons && s.hasIcons {
            if let icon = e.icon, let img = image(icon) {
                let side = t.iconSize
                var rect = NSRect(x: x, y: r.midY - side / 2, width: side, height: side)
                if case .image = icon, img.size.width > 0, img.size.height > 0 {
                    // Keep aspect for clipboard thumbnails.
                    let scale = min(side / img.size.width, side / img.size.height)
                    let w = img.size.width * scale, h = img.size.height * scale
                    rect = NSRect(x: x + (side - w) / 2, y: r.midY - h / 2, width: w, height: h)
                }
                img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            x += t.iconSize + t.elemSpacing
        }

        let lh = t.lineHeight
        let ty = r.minY + (r.height - lh) / 2
        var right = r.maxX - t.elemPad.h
        if let sub = e.sub, !sub.isEmpty {
            let a = NSAttributedString(string: sub, attributes: [.font: t.font, .foregroundColor: c.sub])
            let w = ceil(a.size().width)
            a.draw(at: NSPoint(x: right - w, y: ty))
            right -= w + t.elemSpacing
        }

        let fg = selected ? c.selectedForeground : e.urgent ? c.urgent : e.active ? c.active : c.foreground
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: e.text, attributes: [.font: t.font, .foregroundColor: fg, .paragraphStyle: para])
        if !s.matcher.isEmpty {
            let bold = t.boldFont
            for p in s.matcher.positions(e) where p < e.u16.count {
                text.addAttributes([.foregroundColor: c.match, .font: bold], range: NSRange(location: p, length: 1))
            }
        }
        // Extra height so descenders (g, y, p) aren't clipped; the
        // paragraph style keeps it to one truncated line.
        text.draw(with: NSRect(x: x, y: ty, width: max(0, right - x), height: lh * 1.6),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func fill(_ r: NSRect, radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
    }

    private func image(_ icon: Icon) -> NSImage? {
        let key: String
        switch icon {
        case .file(let p): key = "f:" + p
        case .image(let p): key = "i:" + p
        case .symbol(let n): key = "s:" + n
        case .named(let n): key = "n:" + n
        }
        if let img = icons[key] { return img }
        let img: NSImage?
        switch icon {
        case .file(let p): img = FileManager.default.fileExists(atPath: p) ? NSWorkspace.shared.icon(forFile: p) : nil
        case .image(let p): img = NSImage(contentsOfFile: p)
        case .symbol(let n):
            let conf = NSImage.SymbolConfiguration(pointSize: theme.iconSize * 0.7, weight: .regular)
                .applying(.init(paletteColors: [theme.colors.foreground]))
            img = NSImage(systemSymbolName: n, accessibilityDescription: nil)?.withSymbolConfiguration(conf)
        case .named(let n): img = NSImage(named: n)
        }
        if icons.count > 2000 { icons.removeAll() }
        if let img { icons[key] = img }
        return img
    }

    func clearIconCache() { icons.removeAll() }
}
