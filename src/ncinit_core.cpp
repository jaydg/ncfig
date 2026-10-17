// Only compiled for static builds (xmake f --static=y).
//
// ncpp::NotCurses calls notcurses_init(), which lives in libnotcurses, the
// library that also carries the multimedia (FFmpeg/OpenImageIO) decoders and
// their dependencies. ncfig doesn't decode images, so the static binaries link
// only libnotcurses-core and provide notcurses_init() themselves, as the
// core-only entry point that the library offers for exactly this case.

#include <notcurses/notcurses.h>

extern "C" struct notcurses* notcurses_init(const notcurses_options* opts, FILE* fp)
{
    return notcurses_core_init(opts, fp);
}
