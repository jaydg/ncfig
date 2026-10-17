-- Static linking of Notcurses for the release binaries (xmake f --static=y).
--
-- Instead of the pkgconfig::notcurses++ package, the target gets the compile
-- flags from pkg-config and links libnotcurses++ plus libnotcurses-core and
-- its dependencies (see src/ncinit_core.cpp for why not libnotcurses). On
-- Linux the whole binary is linked with -static, which needs the *-static
-- packages (Alpine) or static libraries of all dependencies installed. On
-- macOS, where fully static binaries aren't possible, each library is linked
-- from its .a archive when one is found, so that the binary only depends on
-- system libraries.

import("tools")

-- configures `target` to link Notcurses statically
function configure(target)
    if not tools.pkgconfig() then
        raise("target(%s): --static needs pkg-config to locate notcurses", target:name())
    end
    local cflags = tools.pkgconfig_query({"--cflags", "notcurses++"})
    local libs = tools.pkgconfig_query({"--static", "--libs", "notcurses-core"})
    if not cflags or not libs then
        raise("target(%s): --static needs notcurses installed with its static libraries\n" ..
              "    check: pkg-config --static --libs notcurses-core", target:name())
    end

    target:add("cxxflags", cflags, {force = true})
    target:add("files", path.join(os.projectdir(), "src", "ncinit_core.cpp"))

    local linkdirs, links, ldflags = {}, {"notcurses++"}, {}
    for _, flag in ipairs(libs:split("%s+")) do
        if flag:startswith("-L") then
            table.insert(linkdirs, flag:sub(3))
        elseif flag:startswith("-l") then
            table.insert(links, flag:sub(3))
        else
            table.insert(ldflags, flag)
        end
    end
    -- libnotcurses-core uses libdeflate, but the .pc file doesn't say so
    if tools.pkgconfig_query({"--exists", "libdeflate"}) then
        for _, flag in ipairs((tools.pkgconfig_query({"--libs-only-L", "libdeflate"}) or ""):split("%s+")) do
            table.insert(linkdirs, flag:sub(3))
        end
        table.insert(links, "deflate")
    end

    if target:is_plat("macosx") then
        -- libunistring has no .pc file; brew links everything into its prefix
        for _, formula in ipairs({"", "libunistring", "libdeflate", "ncurses"}) do
            local prefix = tools.brew_prefix(formula ~= "" and formula or nil)
            if prefix then
                table.insert(linkdirs, path.join(prefix, "lib"))
            end
        end
        -- libraries that come with macOS and may be linked dynamically
        local system = {m = true, c = true, z = true, pthread = true, dl = true, System = true}
        for _, name in ipairs(links) do
            local archive
            for _, dir in ipairs(linkdirs) do
                local candidate = path.join(dir, "lib" .. name .. ".a")
                if os.isfile(candidate) then
                    archive = candidate
                    break
                end
            end
            if archive then
                table.insert(ldflags, archive)
            elseif system[name] then
                target:add("syslinks", name)
            else
                raise("target(%s): --static: no static library lib%s.a for -l%s found in\n    %s",
                    target:name(), name, name, table.concat(linkdirs, "\n    "))
            end
        end
    else
        target:add("ldflags", "-static", {force = true})
        target:add("syslinks", links)
    end
    target:add("linkdirs", linkdirs)
    target:add("ldflags", ldflags, {force = true})
end
