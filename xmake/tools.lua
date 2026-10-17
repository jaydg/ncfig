-- Helpers shared by the build scripts in this directory: finding pkg-config
-- and Homebrew installations, asking them questions, and identifying clang.

import("lib.detect.find_tool")
import("core.cache.detectcache")

-- the pkg-config tool (pkg-config or pkgconf), or nil
function pkgconfig()
    return find_tool("pkg-config") or find_tool("pkgconf")
end

-- the trimmed output of `pkg-config <args>`, or nil if there is no pkg-config
-- or the call fails
function pkgconfig_query(args)
    local pc = pkgconfig()
    if not pc then
        return nil
    end
    local ok, out = try { function () return true, os.iorunv(pc.program, args) end }
    if ok and out then
        return out:trim()
    end
end

-- the prefix brew installed `formula` to, or brew's own prefix without a
-- formula; nil if brew or the formula isn't installed
function brew_prefix(formula)
    if not find_tool("brew") then
        return nil
    end
    local args = formula and {"--prefix", "--installed", formula} or {"--prefix"}
    local ok, out = try { function () return true, os.iorunv("brew", args) end }
    if ok and out then
        out = out:trim()
        if #out > 0 and os.isdir(out) then
            return out
        end
    end
end

-- the major version reported by `program --version` (nil if unknown), and
-- whether it is Apple's clang. Cached like find_tool's results, keyed by the
-- program's path and modification time, so a build doesn't spawn compilers
-- just to look at them; `xmake f -c` clears the cache.
function clang_version(program)
    local key = program .. "@" .. tostring(os.mtime(program) or 0)
    local info = detectcache:get2("ncfig.clang_version", key)
    if info == nil then
        local ok, out = try { function () return true, os.iorunv(program, {"--version"}) end }
        out = ok and out or ""
        info = {major = out:match("version (%d+)") or false, apple = out:find("Apple clang", 1, true) ~= nil}
        detectcache:set2("ncfig.clang_version", key, info)
        detectcache:save()
    end
    return info.major or nil, info.apple
end
