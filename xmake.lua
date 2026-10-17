add_rules("mode.debug", "mode.release")

-- System dependencies. They are optional at the package level so that a
-- missing one doesn't abort with xmake's terse "must be installed!", but the
-- "preflight" rule below turns a missing one into a diagnosis with fixes.
add_requires("pkgconfig::notcurses++", {optional = true})

-- Checks the compiler and every package a target uses and, on a problem, reports
-- why and how to fix it. Install hints live in xmake/preflight.lua.
rule("preflight")
    on_config(function (target)
        import("preflight", {rootdir = path.join(os.projectdir(), "xmake")})
        preflight.check(target)
    end)
rule_end()

-- `xmake f --static=y` links Notcurses and its dependencies statically, so
-- that the binary runs without them installed. Used for the release builds;
-- see xmake/static.lua.
option("static")
    set_default(false)
    set_showmenu(true)
    set_description("Link Notcurses statically (release binaries)")
option_end()

rule("notcurses")
    on_load(function (target)
        if has_config("static") then
            import("static", {rootdir = path.join(os.projectdir(), "xmake")})
            static.configure(target)
        else
            target:add("packages", "pkgconfig::notcurses++")
        end
    end)
rule_end()

-- `xmake fonts` downloads the standard FIGlet fonts into fonts/ so that the
-- examples in the README work. Implementation in xmake/fonts.lua.
task("fonts")
    set_category("action")
    set_menu {
        usage = "xmake fonts",
        description = "Download the standard FIGlet fonts into fonts/",
        options = {},
    }
    on_run(function ()
        import("fonts", {rootdir = path.join(os.projectdir(), "xmake")})
        fonts.fetch()
    end)
task_end()

target("figlet-core")
    set_kind("static")
    set_languages("cxx20")
    add_files("src/canvas.cppm", "src/tweening.cppm", "src/figlet.cppm", {public = true})
    add_headerfiles("src/canvas.cppm", "src/tweening.cppm", "src/figlet.cppm")

target("ncfig")
    set_kind("binary")
    set_languages("cxx20")
    add_rules("preflight", "notcurses")
    add_deps("figlet-core")
    add_files("src/ncfig.cpp", "src/cmdline.cppm")
    -- `xmake install` ships the fonts from `xmake fonts`, where the tools
    -- look for fonts given by name (see FigletFont::fontDirs)
    add_installfiles("fonts/*.flf", {prefixdir = "share/ncfig/fonts"})

target("ncmarquee")
    set_kind("binary")
    set_languages("cxx20")
    add_rules("preflight", "notcurses")
    add_deps("figlet-core")
    add_files("src/ncmarquee.cpp", "src/cmdline.cppm")
