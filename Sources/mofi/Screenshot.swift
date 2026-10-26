import AppKit

/// `mofi -screenshot out.png -show MODE ...`: renders the real launcher view
/// offscreen and composites it onto a generated tiling-WM desktop. No window
/// is ever shown. Used for the README images (scripts/screenshots.sh).
enum Screenshot {
    static let W: CGFloat = 1600
    static let H: CGFloat = 1000
    static let scale: CGFloat = 2

    static func hex(_ s: String, _ a: CGFloat = 1) -> NSColor { NSColor(hex: s)!.withAlphaComponent(a) }

    static func run(out: String, names: [String], start: String?, opts: [String: Any], dmenu: [String]?) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Shell.setupPath()
        let d = Daemon(checkOnly: true)
        Daemon.shared = d
        if let e = d.reload() { fail(e) }

        let session: Session
        if let lines = dmenu {
            let m = DmenuMode(lines: lines, prompt: opts["prompt"] as? String ?? "dmenu", message: opts["message"] as? String,
                              noCustom: true, format: "s")
            session = Session(modes: [m], current: 0) { _, _ in }
        } else {
            var modes: [Mode] = []
            var current = 0
            for n in names {
                guard let m = d.makeMode(n) else { continue }
                if n == start { current = modes.count }
                modes.append(m)
            }
            guard !modes.isEmpty else { fail("no modes to render") }
            session = Session(modes: modes, current: current) { _, _ in }
            session.extraMessage = opts["message"] as? String
        }
        if let f = opts["filter"] as? String {
            session.query = Array(f)
            session.cursor = session.query.count
        }
        if let r = int(opts["selected_row"]) { session.initialRow = r }
        session.linesOverride = int(opts["lines"])

        let t = d.config.theme
        let panelW = t.widthIsPercent ? floor(W * t.width) : t.width
        let panel = d.launcher.renderOffscreen(session, width: panelW, scale: scale)

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: W, height: H)
        NSGraphicsContext.saveGraphicsState()
        let bctx = NSGraphicsContext(bitmapImageRep: rep)!
        // Flip once at the CG level and tell AppKit, so text stays upright
        // and everything lays out top-down like the launcher.
        let cg = bctx.cgContext
        cg.translateBy(x: 0, y: H)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

        drawDesktop(font: t.font.fontName)

        // dim the desktop a touch so the launcher pops
        hex("#000000", 0.28).setFill()
        NSRect(x: 0, y: 0, width: W, height: H).fill()

        let ph = panel.size.height
        let r = NSRect(x: floor((W - panelW) / 2), y: floor((H - ph) / 2) + 10, width: panelW, height: ph)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = hex("#000000", 0.75)
        sh.shadowBlurRadius = 48
        sh.shadowOffset = NSSize(width: 0, height: -18)
        sh.set()
        hex("#000000").setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 2), xRadius: t.radius, yRadius: t.radius).fill()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: panel.size)
        img.addRepresentation(panel)
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("png encode failed") }
        do { try png.write(to: URL(fileURLWithPath: out)) } catch { fail("\(error)") }
        print("wrote \(out)")
        exit(0)
    }

    // MARK: desktop

    typealias Seg = (String, String) // text, color

    static func drawDesktop(font: String) {
        // wallpaper: tokyo-night gradient with soft glows
        let g = NSGradient(colors: [hex("#0b0b14"), hex("#16161e"), hex("#1a1b2e")])!
        g.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -60)
        glow(NSPoint(x: W * 0.82, y: H * 0.22), 620, hex("#7aa2f7", 0.40))
        glow(NSPoint(x: W * 0.15, y: H * 0.85), 640, hex("#bb9af7", 0.34))
        glow(NSPoint(x: W * 0.5, y: H * 0.5), 460, hex("#33ccff", 0.16))

        let mono = NSFont(name: font, size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let monoSmall = NSFont(name: font, size: 12.5) ?? mono
        bar(mono)

        let gap: CGFloat = 12
        let top: CGFloat = 34 + gap
        let left = NSRect(x: gap, y: top, width: (W - gap * 3) * 0.58, height: H - top - gap)
        let rx = left.maxX + gap
        let rw = W - rx - gap
        let rh = (left.height - gap) / 2
        let rt = NSRect(x: rx, y: top, width: rw, height: rh)
        let rb = NSRect(x: rx, y: top + rh + gap, width: rw, height: rh)

        window(left, title: "nvim ~/.config/mofi/init.lua", focused: false)
        lines(editorText, in: left, font: monoSmall, numbered: true)
        window(rt, title: "~", focused: false)
        fetch(in: rt, font: mono)
        window(rb, title: "~/dots", focused: false)
        lines(shellText, in: rb, font: mono, numbered: false)
    }

    static func glow(_ c: NSPoint, _ radius: CGFloat, _ color: NSColor) {
        let g = NSGradient(colors: [color, color.withAlphaComponent(0)])!
        g.draw(fromCenter: c, radius: 0, toCenter: c, radius: radius, options: [])
    }

    static func text(_ s: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    }

    static func bar(_ font: NSFont) {
        let r = NSRect(x: 0, y: 0, width: W, height: 34)
        hex("#000000", 0.82).setFill()
        r.fill()
        hex("#292e42").setFill()
        NSRect(x: 0, y: 33, width: W, height: 1).fill()
        var x: CGFloat = 14
        for (i, ws) in ["1", "2", "3", "4", "5"].enumerated() {
            let active = i == 0
            let pill = NSRect(x: x, y: 7, width: 26, height: 20)
            (active ? hex("#33ccff") : hex("#292e42")).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
            let a = text(ws, font, active ? hex("#000000") : hex("#565f89"))
            a.draw(at: NSPoint(x: pill.midX - a.size().width / 2, y: pill.midY - a.size().height / 2))
            x += 32
        }
        text("  mofi — alt-space", font, hex("#565f89")).draw(at: NSPoint(x: x + 10, y: 8))
        let clock = text("Mon Oct 26  19:42", font, hex("#c0caf5"))
        clock.draw(at: NSPoint(x: W / 2 - clock.size().width / 2, y: 8))
        let right = NSMutableAttributedString()
        for (s, c) in [("\u{f2db} 12%   ", "#9ece6a"), ("\u{f538} 7.1G   ", "#7aa2f7"), ("\u{f05a9} home   ", "#bb9af7"), ("\u{f0079} 87%", "#e0af68")] {
            right.append(text(s, font, hex(c)))
        }
        right.draw(at: NSPoint(x: W - 16 - right.size().width, y: 8))
    }

    static func window(_ r: NSRect, title: String, focused: Bool) {
        hex("#000000", 0.80).setFill()
        let p = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        p.fill()
        (focused ? hex("#33ccff") : hex("#292e42")).setStroke()
        p.lineWidth = 2
        p.stroke()
    }

    static func lines(_ rows: [[Seg]], in r: NSRect, font: NSFont, numbered: Bool) {
        let lh = ceil(font.ascender - font.descender + font.leading) + 3
        var y = r.minY + 16
        for (i, row) in rows.enumerated() {
            guard y + lh < r.maxY - 8 else { break }
            var x = r.minX + 16
            if numbered {
                let n = text(String(format: "%3d", i + 1), font, hex(i == 11 ? "#737aa2" : "#3b4261"))
                n.draw(at: NSPoint(x: x, y: y))
                x += n.size().width + 14
            }
            if i == 11 && numbered {
                hex("#16161e").setFill()
                NSRect(x: x - 6, y: y - 1, width: r.maxX - x - 10, height: lh).fill()
            }
            let a = NSMutableAttributedString()
            for (s, c) in row { a.append(text(s, font, hex(c))) }
            a.draw(at: NSPoint(x: x, y: y))
            y += lh
        }
        if numbered {
            // statusline
            let sl = NSRect(x: r.minX + 2, y: r.maxY - 26, width: r.width - 4, height: 24)
            hex("#16161e").setFill()
            sl.fill()
            let mode = NSRect(x: sl.minX, y: sl.minY, width: 76, height: sl.height)
            hex("#7aa2f7").setFill()
            mode.fill()
            text(" NORMAL", font, hex("#000000")).draw(at: NSPoint(x: mode.minX + 6, y: sl.minY + 4))
            text("  init.lua   lua", font, hex("#a9b1d6")).draw(at: NSPoint(x: mode.maxX + 8, y: sl.minY + 4))
            let pos = text("12:28  ", font, hex("#7aa2f7"))
            pos.draw(at: NSPoint(x: sl.maxX - pos.size().width - 6, y: sl.minY + 4))
        }
    }

    static func fetch(in r: NSRect, font: NSFont) {
        let big = NSFont(name: font.fontName, size: 64) ?? font
        let logo = text("\u{f179}", big, hex("#7aa2f7"))
        logo.draw(at: NSPoint(x: r.minX + 34, y: r.minY + 54))
        let info: [[Seg]] = [
            [("~ ", "#7aa2f7"), ("❯ ", "#9ece6a"), ("fastfetch", "#c0caf5")],
            [("teddy", "#7aa2f7"), ("@", "#c0caf5"), ("macbook", "#7aa2f7")],
            [("─────────────", "#3b4261")],
            [("os       ", "#bb9af7"), ("macOS 27", "#c0caf5")],
            [("wm       ", "#bb9af7"), ("AeroSpace", "#c0caf5")],
            [("launcher ", "#bb9af7"), ("mofi \(mofiVersion)", "#c0caf5")],
            [("shell    ", "#bb9af7"), ("bash 5.3", "#c0caf5")],
            [("term     ", "#bb9af7"), ("alacritty", "#c0caf5")],
            [("font     ", "#bb9af7"), ("Iosevka Nerd Font", "#c0caf5")],
        ]
        let lh = ceil(font.ascender - font.descender + font.leading) + 3
        var y = r.minY + 16
        for row in info {
            let a = NSMutableAttributedString()
            for (s, c) in row { a.append(text(s, font, hex(c))) }
            a.draw(at: NSPoint(x: r.minX + (row.first?.0 == "~ " ? 16 : 150), y: y))
            y += lh
        }
        var x = r.minX + 150
        y += 6
        for c in ["#32344a", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#33ccff", "#c0caf5"] {
            hex(c).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 22, height: 14), xRadius: 3, yRadius: 3).fill()
            x += 26
        }
    }

    static let kw = "#bb9af7", str = "#9ece6a", fn = "#7aa2f7", cm = "#565f89", fg = "#c0caf5", num = "#ff9e64", op = "#89ddff"

    static var editorText: [[Seg]] {
        [
            [("-- ~/.config/mofi/init.lua", cm)],
            [("mofi", fg), (".", op), ("setup", fn), ("({", op)],
            [("  modi ", fg), ("= ", op), ("{ ", op), ("\"drun\"", str), (", ", op), ("\"run\"", str), (", ", op), ("\"clipboard\"", str), (", ", op), ("\"ssh\"", str), (" },", op)],
            [("  matching ", fg), ("= ", op), ("\"fuzzy\"", str), (",", op)],
            [("  theme ", fg), ("= ", op), ("{", op)],
            [("    font ", fg), ("= ", op), ("\"Iosevka Nerd Font\"", str), (", ", op), ("font_size ", fg), ("= ", op), ("14", num), (",", op)],
            [("    width ", fg), ("= ", op), ("\"42%\"", str), (", ", op), ("lines ", fg), ("= ", op), ("10", num), (", ", op), ("radius ", fg), ("= ", op), ("10", num), (",", op)],
            [("    colors ", fg), ("= ", op), ("{ ", op), ("border ", fg), ("= ", op), ("\"#33ccff\"", str), (", ", op), ("background ", fg), ("= ", op), ("\"#000000\"", str), (" },", op)],
            [("  },", op)],
            [("})", op)],
            [("", fg)],
            [("mofi", fg), (".", op), ("bind", fn), ("(", op), ("\"alt-space\"", str), (", ", op), ("\"drun\"", str), (")", op)],
            [("mofi", fg), (".", op), ("bind", fn), ("(", op), ("\"alt-]\"", str), (", ", op), ("\"clipboard\"", str), (")", op)],
            [("", fg)],
            [("mofi", fg), (".", op), ("mode", fn), ("(", op), ("\"power\"", str), (", {", op)],
            [("  items ", fg), ("= ", op), ("{ ", op), ("\"lock\"", str), (", ", op), ("\"sleep\"", str), (", ", op), ("\"restart\"", str), (", ", op), ("\"shutdown\"", str), (" },", op)],
            [("  on_select ", fg), ("= ", op), ("function", kw), ("(", op), ("item", "#e0af68"), (")", op)],
            [("    mofi", fg), (".", op), ("exec", fn), ("(", op), ("cmds", fg), ("[", op), ("item", "#e0af68"), (".", op), ("text", fg), ("])", op)],
            [("  end", kw), (",", op)],
            [("})", op)],
            [("", fg)],
            [("-- live search: items(query) runs on every keystroke", cm)],
            [("mofi", fg), (".", op), ("mode", fn), ("(", op), ("\"calc\"", str), (", { ", op), ("dynamic ", fg), ("= ", op), ("true", num), (", ", op), ("items ", fg), ("= ", op), ("function", kw), ("(", op), ("q", "#e0af68"), (")", op)],
            [("  local ", kw), ("f ", fg), ("= ", op), ("load", fn), ("(", op), ("\"return \" ", str), ("..", op), (" q", "#e0af68"), (")", op)],
            [("  return ", kw), ("{ ", op), ("f ", fg), ("and ", kw), ("tostring", fn), ("(", op), ("f", fg), ("()) ", op), ("or ", kw), ("\"…\"", str), (" }", op)],
            [("end ", kw), ("})", op)],
        ]
    }

    static var shellText: [[Seg]] {
        [
            [("~/dots ", "#7aa2f7"), ("❯ ", "#9ece6a"), ("ls ~/wallpapers | mofi -dmenu -p wallpaper", fg)],
            [("tokyo-night-city.png", "#a9b1d6")],
            [("~/dots ", "#7aa2f7"), ("❯ ", "#9ece6a"), ("mofi -lua 'mofi.config.theme.width'", fg)],
            [("42%", "#a9b1d6")],
            [("~/dots ", "#7aa2f7"), ("❯ ", "#9ece6a"), ("mofi -check", fg)],
            [("ok: ~/.config/mofi/init.lua", "#a9b1d6")],
            [("  modi: drun, run, clipboard, ssh", "#a9b1d6")],
            [("~/dots ", "#7aa2f7"), ("❯ ", "#9ece6a"), ("time mofi -status", fg)],
            [("mofi \(mofiVersion), launcher hidden, 214 clipboard items", "#a9b1d6")],
            [("real 0m0.004s", "#565f89")],
            [("~/dots ", "#7aa2f7"), ("❯ ", "#9ece6a"), ("█", fg)],
        ]
    }
}
