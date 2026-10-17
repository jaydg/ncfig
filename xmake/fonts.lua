-- Fetches the standard FIGlet fonts into fonts/ for the examples in the README.
--
-- The fonts come from Claudio Matsuoka's figlet-fonts collection, which keeps
-- the FIGlet standard distribution fonts (banner, standard, big, slant, ...)
-- in its `ours` directory. The repository is cloned shallowly into build/ and
-- only those fonts are copied, flat, into fonts/. Re-running updates the clone
-- and copies again.

import("devel.git")
import("lib.detect.find_tool")

local url    = "https://github.com/cmatsuoka/figlet-fonts.git"
local subdir = "ours"   -- the FIGlet standard distribution fonts

function fetch()
    if not find_tool("git") then
        raise("git is required to download the fonts")
    end

    local clonedir = path.join(os.projectdir(), "build", "figlet-fonts")
    local fontsdir = path.join(os.projectdir(), "fonts")

    if os.isdir(path.join(clonedir, ".git")) then
        cprint("updating %s", clonedir)
        git.pull({repodir = clonedir})
    else
        os.tryrm(clonedir)   -- leftovers of an interrupted clone
        cprint("cloning %s", url)
        git.clone(url, {depth = 1, outputdir = clonedir})
    end

    local files = os.files(path.join(clonedir, subdir, "*.flf"))
    assert(#files > 0, "no fonts found in %s/%s", clonedir, subdir)

    os.mkdir(fontsdir)
    for _, file in ipairs(files) do
        os.cp(file, fontsdir)
    end
    cprint("${bright}%d fonts copied to %s", #files, fontsdir)
end
