import Darwin
import Foundation
import JugglerCore

/// Thin POSIX wrappers for the MCP transport: a Unix domain socket with newline-delimited messages.
enum UnixSocket {
    struct SocketError: Error, CustomStringConvertible {
        let operation: String
        let code: Int32

        var description: String { "\(operation): \(String(cString: strerror(code))) (\(code))" }
    }

    /// Creates, binds and listens on `path` (a stale socket file is removed first). Non-blocking,
    /// so `accept` can be driven by a `DispatchSource`.
    static func listen(path: String, backlog: Int32 = 8) throws -> Int32 {
        var address = try self.address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError(operation: "socket", code: errno) }
        unlink(path)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw SocketError(operation: "bind \(path)", code: code)
        }
        guard Darwin.listen(fd, backlog) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw SocketError(operation: "listen", code: code)
        }
        setNonBlocking(fd, true)
        return fd
    }

    /// Connects to the socket at `path`; `nil` if nobody is listening (Juggler is not running or MCP is off).
    static func connect(path: String) -> Int32? {
        guard var address = try? self.address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            return nil
        }
        prepareStream(fd)
        return fd
    }

    /// Accepted or connected stream: blocking reads, no SIGPIPE on a write to a closed peer.
    static func prepareStream(_ fd: Int32) {
        setNonBlocking(fd, false)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    static func setNonBlocking(_ fd: Int32, _ on: Bool) {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return }
        _ = fcntl(fd, F_SETFL, on ? flags | O_NONBLOCK : flags & ~O_NONBLOCK)
    }

    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !bytes.isEmpty, bytes.count < capacity else {
            throw SocketError(operation: "socket path \(path)", code: ENAMETOOLONG)
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return address
    }

    /// Writes the whole string plus a newline. `false` if the peer is gone.
    static func writeLine(_ fd: Int32, _ line: String) -> Bool {
        var bytes = Array(line.utf8)
        bytes.append(0x0A)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            offset += written
        }
        return true
    }

    /// Splits a blocking byte stream into lines (without the `\n`).
    final class LineReader {
        private var buffer: [UInt8] = []
        private var chunk = [UInt8](repeating: 0, count: 64 * 1024)

        /// The next line, or `nil` at end of stream. A final line without `\n` is returned before `nil`.
        func next(from fd: Int32) -> String? {
            while true {
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = String(decoding: buffer[..<newline], as: UTF8.self)
                    buffer.removeSubrange(...newline)
                    return line
                }
                let count = Darwin.read(fd, &chunk, chunk.count)
                if count < 0, errno == EINTR { continue }
                if count <= 0 {
                    guard !buffer.isEmpty else { return nil }
                    let rest = String(decoding: buffer, as: UTF8.self)
                    buffer.removeAll()
                    return rest
                }
                buffer.append(contentsOf: chunk[..<count])
            }
        }
    }
}
