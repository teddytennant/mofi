import Foundation

/// One JSON object per line over a Unix socket: the client writes a request,
/// the daemon writes one response and closes.
enum IPC {
    static func address(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            let n = min(bytes.count, buf.count - 1)
            for i in 0..<n { buf[i] = bytes[i] }
            buf[n] = 0
        }
        return addr
    }

    static func connect(_ path: String = Paths.socket) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = address(path)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if ok != 0 {
            close(fd)
            return nil
        }
        return fd
    }

    static func alive() -> Bool {
        guard let fd = connect() else { return false }
        close(fd)
        return true
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }

    static func readLine(_ fd: Int32) -> Data {
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            out.append(buf, count: n)
            if buf[n - 1] == 10 { break }
        }
        return out
    }

    static func encode(_ obj: [String: Any]) -> Data {
        var d = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        d.append(10)
        return d
    }

    static func decode(_ d: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    /// Client side: send and block until the daemon answers.
    static func request(_ obj: [String: Any]) -> [String: Any]? {
        guard let fd = connect() else { return nil }
        defer { close(fd) }
        guard writeAll(fd, encode(obj)) else { return nil }
        return decode(readLine(fd))
    }
}

final class IPCServer {
    typealias Reply = ([String: Any]) -> Void
    private let path: String
    private var fd: Int32 = -1
    private var inode: ino_t = 0
    private let handler: ([String: Any], @escaping Reply) -> Void

    init(path: String, handler: @escaping ([String: Any], @escaping Reply) -> Void) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        Paths.ensure((path as NSString).deletingLastPathComponent)
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LuaError(description: "socket() failed") }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var addr = IPC.address(path)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { throw LuaError(description: "bind(\(path)) failed: \(String(cString: strerror(errno)))") }
        chmod(path, 0o600)
        var st = stat()
        if stat(path, &st) == 0 { inode = st.st_ino }
        guard listen(fd, 16) == 0 else { throw LuaError(description: "listen() failed") }
        let listener = fd
        Thread.detachNewThread { [handler] in
            while true {
                let c = accept(listener, nil, nil)
                if c < 0 { continue }
                _ = fcntl(c, F_SETFD, FD_CLOEXEC)
                DispatchQueue.global().async {
                    let req = IPC.decode(IPC.readLine(c)) ?? [:]
                    DispatchQueue.main.async {
                        var replied = false
                        handler(req) { resp in
                            guard !replied else { return }
                            replied = true
                            _ = IPC.writeAll(c, IPC.encode(resp))
                            close(c)
                        }
                    }
                }
            }
        }
    }

    func stop() {
        if fd >= 0 { close(fd) }
        // A newer daemon may already own the path; only remove our own socket.
        var st = stat()
        if stat(path, &st) == 0, st.st_ino == inode { unlink(path) }
    }
}
