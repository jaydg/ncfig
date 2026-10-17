-- Preflight checks for the build: verifies that every package a target uses
-- was found and, if not, explains why and proposes a fix for this machine.
--
-- To cover a new dependency, add an entry to `hints`. Keys are the names used
-- in add_requires(); `pkgconfig` is the pkg-config module name, and the
-- remaining fields are the package name per system package manager.
-- `pc_providers` does the same for pkg-config modules that a dependency's .pc
-- file requires but whose distribution package doesn't pull in.

import("lib.detect.find_tool")
import("core.project.config")
import("core.project.project")
import("tools")

local hints = {
    ["pkgconfig::notcurses++"] = {
        description = "Notcurses C++ bindings (ncpp/*.hh)",
        source      = "https://github.com/dankamongmen/notcurses/blob/master/INSTALL.md",
        pkgconfig   = "notcurses++",
        brew        = "notcurses",
        apt         = "libnotcurses++-dev",
        dnf         = "notcurses-c++-devel",
        pacman      = "notcurses",
        zypper      = "notcurses-devel",
    },
}

local pc_providers = {
    -- Ubuntu/Debian's libnotcurses-core-dev requires tinfo.pc without depending on it
    tinfo = {apt = "libncurses-dev", dnf = "ncurses-devel", pacman = "ncurses", zypper = "ncurses-devel"},
}

local managers = {
    {name = "brew",   install = "brew install %s"},
    {name = "apt",    install = "sudo apt install %s"},
    {name = "dnf",    install = "sudo dnf install %s"},
    {name = "pacman", install = "sudo pacman -S %s"},
    {name = "zypper", install = "sudo zypper install %s"},
}

-- the `xmake f` command that reconfigures with the toolchain settings in
-- use, so that following a fix doesn't throw them away
local function reconfigure()
    local cmd = "xmake f -c"
    for _, name in ipairs({"toolchain", "sdk"}) do
        local value = config.get(name)
        if value then
            cmd = cmd .. " --" .. name .. "=" .. tostring(value)
        end
    end
    return cmd
end

-- the system package managers available here, in order of preference
local function available_managers()
    local found = {}
    for _, m in ipairs(managers) do
        local program = m.name == "apt" and "apt-get" or m.name
        if find_tool(program) then
            table.insert(found, m)
        end
    end
    return found
end

-- the pkg-config module that `module` requires but that is not installed,
-- or nil if pkg-config reports no such problem
local function missing_requirement(module)
    local pkgconfig = tools.pkgconfig()
    if not pkgconfig then
        return
    end
    local errfile = os.tmpfile()
    os.execv(pkgconfig.program, {"--print-errors", "--exists", module}, {try = true, stderr = errfile})
    local errors = os.isfile(errfile) and io.readfile(errfile) or ""
    os.tryrm(errfile)
    -- pkgconf reports the module itself as "required by 'virtual:world'"
    for required, by in errors:gmatch("Package '([^']+)', required by '([^']+)', not found") do
        if required ~= module and not by:startswith("virtual:") then
            return required
        end
    end
end

-- whether the package manager `manager` can install all of `packages`
-- (space separated); true when this can't be checked
local function installable(manager, packages)
    if manager ~= "apt" then
        return true
    end
    for _, package in ipairs(packages:split(" ")) do
        local ok, out = try { function () return true, os.iorunv("apt-cache", {"show", "--no-all-versions", package}) end }
        if not ok or not out or not out:find("Package:", 1, true) then
            return false
        end
    end
    return true
end

-- appends an install command for each package manager available here that
-- `packages` (manager name -> package name) knows; false if there was none
local function add_install_fixes(lines, packages)
    local added = false
    for _, m in ipairs(available_managers()) do
        if packages[m.name] and not installable(m.name, packages[m.name]) then
            table.insert(lines, string.format("note:  %s has no package %s on this system (try `sudo apt update` first)",
                m.name, packages[m.name]))
        elseif packages[m.name] then
            table.insert(lines, "fix:   " .. string.format(m.install, packages[m.name]) .. " && " .. reconfigure())
            added = true
        end
    end
    return added
end

-- a list of findings and proposed fixes for one missing package
local function diagnose(name)
    local hint = hints[name]
    local lines = {}
    if not hint then
        table.insert(lines, "no install hint known for this package; add one to xmake/preflight.lua")
        return lines
    end

    table.insert(lines, "provides: " .. hint.description)

    if hint.pkgconfig and not tools.pkgconfig() then
        table.insert(lines, "cause: pkg-config is not installed, so xmake cannot look up " .. hint.pkgconfig)
        add_install_fixes(lines, {brew = "pkgconf", apt = "pkg-config", dnf = "pkgconf", pacman = "pkgconf", zypper = "pkgconf"})
        return lines
    end

    if hint.pkgconfig then
        local required = missing_requirement(hint.pkgconfig)
        if required then
            table.insert(lines, string.format("cause: %s is installed, but the %s pkg-config module it requires is missing",
                hint.pkgconfig, required))
            if not add_install_fixes(lines, pc_providers[required] or {}) then
                table.insert(lines, "fix:   install the development package that provides " .. required .. ".pc")
            end
            table.insert(lines, "check: pkg-config --print-errors --modversion " .. hint.pkgconfig)
            return lines
        end
    end

    if hint.brew then
        local prefix = tools.brew_prefix(hint.brew)
        if prefix then
            local pcdir = path.join(prefix, "lib", "pkgconfig")
            table.insert(lines, "cause: " .. hint.brew .. " is installed at " .. prefix .. " but pkg-config does not see it")
            table.insert(lines, "fix:   export PKG_CONFIG_PATH=\"" .. pcdir .. ":$PKG_CONFIG_PATH\" && " .. reconfigure())
            return lines
        end
    end

    table.insert(lines, "cause: the package is not installed")
    if not add_install_fixes(lines, hint) then
        table.insert(lines, "fix:   build it from source" .. (hint.source and (" (" .. hint.source .. ")") or "")
            .. " and make sure pkg-config finds " .. (hint.pkgconfig or name))
    end
    if hint.pkgconfig then
        table.insert(lines, "check: pkg-config --modversion " .. hint.pkgconfig)
    end
    return lines
end

-- `program` as an absolute path, looked up in PATH if needed
local function resolve(program)
    if path.is_absolute(program) then
        return program
    end
    for _, dir in ipairs(path.splitenv(os.getenv("PATH") or "")) do
        local candidate = path.join(dir, program)
        if os.isexec(candidate) then
            return candidate
        end
    end
end

-- `program` with symlinks resolved
local function follow_links(program)
    for _ = 1, 16 do
        if not os.islink(program) then
            break
        end
        local target = os.readlink(program)
        program = path.is_absolute(target) and target or path.join(path.directory(program), target)
    end
    return program
end

-- how to install a clang-scan-deps matching clang `major` on this machine
local function scanner_fixes(lines, major, apple)
    if apple then
        table.insert(lines, "fix:   brew install llvm && xmake f -c --toolchain=llvm --sdk=$(brew --prefix llvm)")
        return
    end
    local packages = {
        brew = "llvm", apt = "clang-tools-" .. (major or "<version>"),
        dnf = "clang-tools-extra", pacman = "clang", zypper = "clang-tools",
    }
    if not add_install_fixes(lines, packages) then
        table.insert(lines, "fix:   install the clang-scan-deps that comes with clang " .. (major or ""))
    end
end

-- C++ modules need their dependencies scanned by clang-scan-deps. xmake
-- takes it from the compiler's directory or, failing that, from PATH, which
-- can yield a scanner from a different LLVM than the compiler (e.g. Homebrew
-- LLVM's next to Apple clang). That scanner then can't find the compiler's
-- builtin headers and fails with "'stdarg.h' file not found".
local function check_module_scanner(target)
    local has_modules = false
    for _, file in ipairs(target:sourcefiles()) do
        if file:endswith(".cppm") or file:endswith(".mpp") or file:endswith(".ixx") then
            has_modules = true
            break
        end
    end
    if not has_modules then
        return
    end

    local program, toolname = target:tool("cxx")
    if not program or not toolname or not toolname:find("clang", 1, true) then
        return
    end
    program = resolve(program) or program
    local cxx_major, apple = tools.clang_version(program)

    -- a scanner shipped with the compiler, e.g. /usr/lib/llvm-18/bin on
    -- Debian/Ubuntu (where /usr/bin only has clang-scan-deps-18)
    local names = {"clang-scan-deps"}
    if cxx_major then
        table.insert(names, "clang-scan-deps-" .. cxx_major)
    end
    for _, dir in ipairs(table.unique({path.directory(program), path.directory(follow_links(program))})) do
        for _, name in ipairs(names) do
            if os.isexec(path.join(dir, name)) then
                return
            end
        end
    end
    if cxx_major and not apple and find_tool("clang-scan-deps-" .. cxx_major) then
        return
    end

    local lines = {}
    local scanner = find_tool("clang-scan-deps")
    if not scanner then
        table.insert(lines, "cause: C++ modules need clang-scan-deps, but none was found for " .. program)
        scanner_fixes(lines, cxx_major, apple)
        return lines
    end

    local scan_major = tools.clang_version(scanner.program)
    if cxx_major and scan_major and cxx_major == scan_major and not apple then
        return
    end

    table.insert(lines, string.format("cause: compiling with %sclang %s (%s) but scanning modules with clang-scan-deps %s (%s);",
        apple and "Apple " or "", cxx_major or "?", program, scan_major or "?", scanner.program))
    table.insert(lines, "       the scanner can't find the compiler's builtin headers (\"'stdarg.h' file not found\")")
    if apple then
        local llvm = path.directory(path.directory(scanner.program))
        table.insert(lines, "fix:   use one toolchain for both: xmake f -c --toolchain=llvm --sdk=" .. llvm)
    else
        scanner_fixes(lines, cxx_major, apple)
    end
    return lines
end

-- GCC up to 15 fails on notcurses' headers when they meet C++ modules:
-- 13 and 14 with "conflicting global module declaration" (ncpp::Plane::translate),
-- 15 with "exposes TU-local entity" (ncpp::Plane::load). GCC 16 works.
local function check_gcc(target)
    if not table.contains(table.wrap(target:get("packages")), "pkgconfig::notcurses++") then
        return
    end
    local program, toolname = target:tool("cxx")
    if not program or not toolname or not (toolname == "gxx" or toolname == "gcc") then
        return
    end
    local ok, out = try { function () return true, os.iorunv(program, {"-dumpversion"}) end }
    local major = ok and out and tonumber(out:match("^(%d+)"))
    if not major or major > 15 then
        return
    end

    local lines = {
        string.format("cause: GCC %d (%s) can't compile the notcurses headers together with C++ modules", major, program),
        string.format("       (%s in ncpp/Plane.hh); use clang or GCC 16+",
            major >= 15 and "\"exposes TU-local entity\"" or "\"conflicting global module declaration\""),
    }
    if find_tool("clang++") then
        table.insert(lines, "fix:   xmake f -c --toolchain=clang")
    elseif add_install_fixes(lines, {apt = "clang clang-tools", dnf = "clang clang-tools-extra", pacman = "clang", zypper = "clang"}) then
        lines[#lines] = lines[#lines]:gsub("xmake f %-c$", "xmake f -c --toolchain=clang")
    end
    return lines
end

-- how to treat problems that concern only `target` (its compiler support and
-- its packages) in this run of xmake:
--   "warn"  on an explicit `xmake f`, so that the configuration is saved; the
--           next build configures again and reports them as errors
--   "skip"  when the command line names other targets that don't depend on
--           `target` (e.g. `xmake build figlet-core`)
--   "raise" otherwise
-- The configure step runs as a nested task with options of its own, so the
-- targets named on the command line are only visible in xmake.argv().
local function severity(target)
    local argv = table.wrap(xmake.argv())
    if argv[1] == "f" or argv[1] == "config" then
        return "warn"
    end
    local named = false
    for _, arg in ipairs(argv) do
        local other = not arg:startswith("-") and project.target(arg)
        if other then
            named = true
            if other:name() == target:name() then
                return "raise"
            end
            for _, dep in ipairs(other:orderdeps()) do
                if dep:name() == target:name() then
                    return "raise"
                end
            end
        end
    end
    return named and "skip" or "raise"
end

-- raises a build error listing every problem found for `target`, or a warning
-- (see severity above)
function check(target)
    -- a mismatched module scanner breaks every target, so it is always an error
    local scanner_problem = check_module_scanner(target)
    if scanner_problem then
        raise("target(%s): toolchain mismatch\n    %s", target:name(), table.concat(scanner_problem, "\n    "))
    end

    local how = severity(target)
    if how == "skip" then
        return
    end
    local report = function (fmt, ...)
        if how == "warn" then
            utils.warning(fmt, ...)
        else
            raise(fmt, ...)
        end
    end

    local gcc_problem = check_gcc(target)
    if gcc_problem then
        report("target(%s): unsupported compiler\n    %s", target:name(), table.concat(gcc_problem, "\n    "))
        return
    end

    local missing = {}
    for _, name in ipairs(table.wrap(target:get("packages"))) do
        local pkg = target:pkg(name)
        if not pkg or not pkg:enabled() then
            table.insert(missing, name)
        end
    end
    if #missing == 0 then
        return
    end

    local lines = {}
    for _, name in ipairs(missing) do
        table.insert(lines, "  " .. name)
        for _, line in ipairs(diagnose(name)) do
            table.insert(lines, "    " .. line)
        end
    end
    report("target(%s): missing dependencies\n%s", target:name(), table.concat(lines, "\n"))
end
