import CLua
import Foundation

typealias LuaFn = @convention(c) (OpaquePointer?) -> Int32

struct LuaError: Error, CustomStringConvertible {
    let description: String
}

/// Stand-in for a Lua function when a table is converted to Swift values.
struct LuaFunctionRef {}

private let traceback: LuaFn = { L in
    if let msg = mofi_tostring(L, 1) {
        luaL_traceback(L, L, msg, 1)
    } else {
        luaL_traceback(L, L, "(error object is not a string)", 1)
    }
    return 1
}

/// Thin wrapper over one lua_State. All calls happen on the main thread.
final class LuaVM {
    let L: OpaquePointer

    init() {
        L = luaL_newstate()
        luaL_openlibs(L)
    }

    deinit { lua_close(L) }

    func setGlobal(table name: String, functions: [String: LuaFn], fields: [String: Any]) {
        mofi_newtable(L)
        for (k, f) in functions {
            mofi_pushcfunction(L, f)
            lua_setfield(L, -2, k)
        }
        for (k, v) in fields {
            LuaVM.push(L, v)
            lua_setfield(L, -2, k)
        }
        lua_setglobal(L, name)
    }

    func exec(_ code: String, name: String) throws {
        let bytes = Array(code.utf8)
        let st = bytes.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bytes.count) {
                luaL_loadbufferx(L, $0, bytes.count, "=" + name, nil)
            }
        }
        if st != LUA_OK { throw LuaError(description: popString()) }
        try pcall(nargs: 0, nresults: 0)
    }

    func execFile(_ path: String) throws {
        if luaL_loadfilex(L, path, nil) != LUA_OK { throw LuaError(description: popString()) }
        try pcall(nargs: 0, nresults: 0)
    }

    /// Call `mofi.<name>(args...)` and return `results` values.
    @discardableResult
    func call(_ name: String, _ args: [Any?], results n: Int32 = 1) throws -> [Any?] {
        let top = lua_gettop(L)
        lua_getglobal(L, "mofi")
        guard lua_type(L, -1) == LUA_TTABLE else {
            lua_settop(L, top)
            throw LuaError(description: "the global `mofi` table is missing")
        }
        lua_getfield(L, -1, name)
        mofi_remove(L, -2)
        guard lua_type(L, -1) == LUA_TFUNCTION else {
            lua_settop(L, top)
            throw LuaError(description: "mofi.\(name) is not a function")
        }
        for a in args { LuaVM.push(L, a) }
        do {
            try pcall(nargs: Int32(args.count), nresults: n)
        } catch {
            lua_settop(L, top)
            throw error
        }
        var out: [Any?] = []
        for i in 0..<n { out.append(LuaVM.value(L, top + 1 + i)) }
        lua_settop(L, top)
        return out
    }

    /// Read a global by dotted path, e.g. "mofi.config".
    func global(_ path: String) -> Any? {
        let top = lua_gettop(L)
        defer { lua_settop(L, top) }
        let parts = path.split(separator: ".").map(String.init)
        lua_getglobal(L, parts[0])
        for p in parts.dropFirst() {
            guard lua_type(L, -1) == LUA_TTABLE else { return nil }
            lua_getfield(L, -1, p)
        }
        return LuaVM.value(L, -1)
    }

    private func pcall(nargs: Int32, nresults: Int32) throws {
        let base = lua_gettop(L) - nargs
        mofi_pushcfunction(L, traceback)
        mofi_insert(L, base)
        let st = mofi_pcall(L, nargs, nresults, base)
        mofi_remove(L, base)
        if st != LUA_OK { throw LuaError(description: popString()) }
    }

    private func popString() -> String {
        let s = LuaVM.string(L, -1) ?? "unknown Lua error"
        mofi_pop(L, 1)
        return s
    }

    // MARK: - value conversion (static so C callbacks can use them)

    static func string(_ L: OpaquePointer?, _ i: Int32) -> String? {
        let t = lua_type(L, i)
        guard t == LUA_TSTRING || t == LUA_TNUMBER else { return nil }
        var len = 0
        guard let p = lua_tolstring(L, i, &len) else { return nil }
        return String(decoding: UnsafeRawBufferPointer(start: p, count: len), as: UTF8.self)
    }

    static func push(_ L: OpaquePointer?, _ v: Any?) {
        guard let v else { lua_pushnil(L); return }
        switch v {
        case is NSNull:
            lua_pushnil(L)
        case let b as Bool:
            lua_pushboolean(L, b ? 1 : 0)
        case let i as Int:
            lua_pushinteger(L, lua_Integer(i))
        case let i as Int32:
            lua_pushinteger(L, lua_Integer(i))
        case let i as UInt32:
            lua_pushinteger(L, lua_Integer(i))
        case let d as Double:
            lua_pushnumber(L, d)
        case let s as String:
            let bytes = Array(s.utf8)
            if bytes.isEmpty {
                lua_pushstring(L, "")
            } else {
                bytes.withUnsafeBufferPointer { buf in
                    buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bytes.count) {
                        _ = lua_pushlstring(L, $0, bytes.count)
                    }
                }
            }
        case let a as [Any?]:
            lua_createtable(L, Int32(a.count), 0)
            for (i, x) in a.enumerated() {
                push(L, x)
                lua_rawseti(L, -2, lua_Integer(i + 1))
            }
        case let a as [Any]:
            push(L, a.map { Optional($0) })
        case let d as [String: Any]:
            lua_createtable(L, 0, Int32(d.count))
            for (k, x) in d {
                push(L, x)
                lua_setfield(L, -2, k)
            }
        default:
            lua_pushnil(L)
        }
    }

    /// Convert the value at `idx` to Swift: Bool, Int, Double, String,
    /// [Any] (sequence tables), [String: Any] (other tables), LuaFunctionRef.
    static func value(_ L: OpaquePointer?, _ idx: Int32, depth: Int = 0) -> Any? {
        let i = lua_absindex(L, idx)
        switch lua_type(L, i) {
        case LUA_TBOOLEAN:
            return lua_toboolean(L, i) != 0
        case LUA_TNUMBER:
            if lua_isinteger(L, i) != 0 { return Int(mofi_tointeger(L, i)) }
            return mofi_tonumber(L, i)
        case LUA_TSTRING:
            return string(L, i)
        case LUA_TFUNCTION:
            return LuaFunctionRef()
        case LUA_TTABLE:
            guard depth < 32 else { return nil }
            var dict: [String: Any] = [:]
            var arr: [Int: Any] = [:]
            lua_pushnil(L)
            while lua_next(L, i) != 0 {
                if let v = value(L, -1, depth: depth + 1) {
                    if lua_type(L, -2) == LUA_TNUMBER, lua_isinteger(L, -2) != 0 {
                        arr[Int(mofi_tointeger(L, -2))] = v
                    } else if lua_type(L, -2) == LUA_TSTRING, let k = string(L, -2) {
                        dict[k] = v
                    }
                }
                mofi_pop(L, 1)
            }
            if dict.isEmpty {
                if arr.isEmpty { return [Any]() }
                if arr.keys.min() == 1, arr.keys.max() == arr.count {
                    return (1...arr.count).map { arr[$0]! }
                }
            }
            for (k, v) in arr { dict[String(k)] = v }
            return dict
        default:
            return nil
        }
    }

    /// Push `nil, message` and return the count, the usual Lua error idiom.
    static func fail(_ L: OpaquePointer?, _ msg: String) -> Int32 {
        lua_pushnil(L)
        push(L, msg)
        return 2
    }
}
