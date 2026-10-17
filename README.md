# ncfig: NotCurses Tools for FIGlet Fonts

A collection of command-line tools for rendering beautiful [FIGlet](https://www.figlet.org/) fonts with [Notcurses](https://github.com/dankamongmen/notcurses), featuring true color gradient support.

![ncfig Logo](/logo.png "ncfig. This was rendered using the font univers.flf")

## Installing

Prebuilt binaries for Linux (x86_64, aarch64; fully static) and macOS 13 or newer (Intel, Apple Silicon) come with every [release](https://github.com/jaydg/ncfig/releases), together with the standard FIGlet fonts. No compiler and no Notcurses installation needed.

**Try it without installing** (downloads to a temporary directory and plays a demo; any key ends it):

```sh
bash <(curl -L https://raw.githubusercontent.com/jaydg/ncfig/main/scripts/launch.sh)
```

The same command runs the tools with your own arguments, e.g. `... launch.sh) ncfig -f slant -v 0xff0000:0x0000ff "Hello"`.

Built it yourself already (see [Building](#building))? `scripts/demo.sh` plays the same demo using your local build in `build/` and the fonts in `fonts/`, with no download needed; without a local build it falls back to downloading a release, same as `launch.sh`. `scripts/download.sh` alone just fetches and caches the release binaries (printing the directory they end up in), which `launch.sh` and `demo.sh` use internally; set `VERSION=v0.1.0` to pin a specific release instead of the latest one.

**Install with a script** into `~/.local/bin` (set `PREFIX` for another location):

```sh
bash <(curl -L https://raw.githubusercontent.com/jaydg/ncfig/main/scripts/install.sh)
```

To build from source instead, see [Building](#building).

## Tools

### ncfig

Renders text to the terminal using FIGlet fonts.

The examples below assume the tools are [installed](#installing). Installed releases ship the standard FIGlet fonts, which can be given by name (`-f banner`); see [Getting Fonts](#getting-fonts).

**Usage:**

```
ncfig -f <font> [-v <gradient>] [-h <gradient>] [-r <gradient>] [text]
```

| Option | Description |
|--------|-------------|
| `-f <font>` | Path to a FIGlet font file (`.flf`) |
| `-v <gradient>` | Vertical color gradient |
| `-h <gradient>` | Horizontal color gradient |
| `-r <gradient>` | Radial color gradient |
| `text` | Text to render (default: `HELLO NOTCURSES!`) |

**Example:**

```
ncfig -f fonts/banner.flf -v 0xff0000:0x0000ff "Hello"
```

Vertical and horizontal gradients can be combined (colors are added channel-wise). Radial gradients are mutually exclusive with the others.

### ncmarquee

Creates a full-screen marquee animation with FIGlet text. The text floats from right to left, and when it has left the visible area entirely, it comes back in from the right. Press any key to exit.

**Usage:**

```
ncmarquee -f <font> [-v <gradient>] [-h <gradient>] [-r <gradient>] [-s <ms>] [-t] [-c] [-w <amplitude>] [text]
```

| Option | Description |
|--------|-------------|
| `-f <font>` | Path to a FIGlet font file (`.flf`) |
| `-v <gradient>` | Vertical color gradient |
| `-h <gradient>` | Horizontal color gradient |
| `-r <gradient>` | Radial color gradient |
| `-s <ms>` | Scroll speed in milliseconds (default: 50) |
| `-t` | Apply gradient and wave to text dimensions (default: apply to the visible area) |
| `-c` | Circular mode (text is directly followed by itself) |
| `-w <amplitude>` | Sine wave vertical movement with the given amplitude in rows |
| `text` | Text to render (default: `HELLO NOTCURSES!`) |

**Examples:**

```
# Default speed (50ms)
ncmarquee -f fonts/standard.flf "MARQUEE"

# Faster animation (20ms delay)
ncmarquee -f fonts/standard.flf -s 20 "HELLO WORLD"

# With gradient
ncmarquee -f fonts/banner.flf -h 0xff0000:0x0000ff -s 30 "NOTCURSES"

# Sine wave with 4-row amplitude
ncmarquee -f fonts/banner.flf -w 4 "WAVE"

# Circular sine wave — seamless across repeated instances
ncmarquee -f fonts/banner.flf -c -w 3 "LOOP"
```

#### Sine wave mode (`-w`)

The `-w <amplitude>` flag adds a vertical sine wave through the scrolling text. Each FIGlet character is displaced independently on the y-axis according to a continuous sine wave, so the text undulates as it scrolls. The amplitude is given in terminal rows.

The `-t` flag controls the wave's frame of reference:

- **`-t` off (default):** the wave is fixed in screen space — each screen column has a fixed y-offset at any moment in time, and the text scrolls through it. In circular mode (`-c`) this means adjacent instances share the same wave seamlessly, with no discontinuity at the wrap point.
- **`-t` on:** the wave is fixed to the text — each character carries its own phase based on its position in the string, so the wave pattern travels with the text as it scrolls.

Because terminal rows are discrete, the wave will always be a staircase of integer row steps between characters rather than a truly smooth curve. Larger amplitudes make individual steps proportionally smaller and less noticeable.

## Gradients

Gradients are specified as pairs of hexadecimal colors separated by a colon:

- `0xff0000` = Red
- `0x00ff00` = Green
- `0x0000ff` = Blue
- `0xffff00` = Yellow
- `0xff00ff` = Magenta
- `0x00ffff` = Cyan

Example: `0xff0000:0x0000ff` creates a red-to-blue gradient. Two colors are mandatory, but you can optionally add a third color as center color, e.g. e.g. 0xff0000:0x00ff00:0x0000ff for a red-to-green-to-blue gradient.

## Getting Fonts

The examples above use the fonts of the FIGlet standard distribution (`banner.flf`, `standard.flf`, `big.flf`, `slant.flf`, ...). The `-f` option takes either the path of a `.flf` file or the name of a font, with or without the extension. Names are looked up in `$NCFIG_FONTDIR`, in `fonts/` next to the executable, in `../share/ncfig/fonts` relative to the executable (where installed releases keep the fonts), and last in the current directory; use `./name.flf` for a file there. So after installing, `-f banner` just works.

When building from source, download these 17 fonts into `fonts/` with

```sh
xmake fonts
```

This clones Claudio Matsuoka's [figlet-fonts](https://github.com/cmatsuoka/figlet-fonts) repository into `build/` and copies the standard fonts out of it. Running it again updates them. `xmake install` installs them along with the tools; while developing, `export NCFIG_FONTDIR=$PWD/fonts` lets you use names with the binaries in `build/`.

For more fonts, I found these sources, two of them on GitHub:

 * The [font database](https://www.figlet.org/cgi-bin/fontdb.cgi) on the FIGlet site allows to browse and preview the fonts.
 * Claudio Matsuoka's repository [figlet-fonts](https://github.com/cmatsuoka/figlet-fonts) has everything the FIGlet font database has plus a lot of extra fonts, easily to be cloned to a local repository. Some of the fonts were automatically generated from old X11 fonts and C64 demo fonts, in these cases the quality is not always optimal.
 * The repository [github.com/xero/figlet-fonts](https://github.com/xero/figlet-fonts) has a huge collection of fonts in a huge single directory, some to be found on the previous two locations, some new.  It is easy to get an overview of the fonts thanks to the [examples page](https://github.com/xero/figlet-fonts/blob/main/Examples.md).

The FIGlet site has a FTP server as well, but as FTP is so very dead I assume you don't have a client for that.

## Building

Requires [xmake](https://xmake.io), a C++ compiler with C++20 modules support (see [Dependencies](#dependencies)) and Notcurses.

On Debian/Ubuntu:

```sh
sudo apt install clang clang-tools pkg-config libnotcurses++-dev libncurses-dev
xmake f --toolchain=clang   # GCC before 16 can't build this, see below
```

`libncurses-dev` is needed because Notcurses' pkg-config files require `tinfo`, which the Notcurses packages don't pull in.

On macOS, install Notcurses and LLVM with Homebrew and build with Homebrew's LLVM, since Apple's clang lacks a matching `clang-scan-deps`:

```sh
brew install notcurses llvm
xmake f --toolchain=llvm --sdk=$(brew --prefix llvm)
```

If something is missing or mismatched, `xmake` stops before compiling, explains the cause and proposes a fix. `xmake f` only warns about what the tools need and still saves the configuration, and `xmake build figlet-core` ignores it.

### Build all tools:

```sh
xmake
```

The binaries end up in `build/<platform>/<arch>/release/`, for example `build/linux/x86_64/release/` or `build/macosx/arm64/release/`:
- `ncfig` - Static FIGlet renderer
- `ncmarquee` - Full-screen marquee animation

### Install the tools:

xmake doesn't put the binaries on your `PATH`; `xmake install` does. Install for your user only:

```sh
xmake install -o ~/.local
```

This puts `ncfig` and `ncmarquee` into `~/.local/bin` and the fonts from `xmake fonts` into `~/.local/share/ncfig/fonts`. Make sure the `bin` directory is on your `PATH` (it is by default on most current Linux distributions, on macOS add `export PATH="$HOME/.local/bin:$PATH"` to your shell profile). Alternatively install system-wide:

```sh
sudo xmake install -o /usr/local
```

`xmake uninstall --installdir=<dir>` with the same directory removes them again.

### Get the fonts for the examples:

```sh
xmake fonts
```

See [Getting Fonts](#getting-fonts).

### Build a specific tool:

```sh
xmake build ncfig
xmake build ncmarquee
```

### Build only the core library (zero external dependencies):

```sh
xmake build figlet-core
```

This compiles `libfiglet-core.a` with `FigletFont`, `TextCanvas`, and `Tweening`
without requiring Notcurses. You can integrate this target into other projects
using `includes(...)` and `add_deps("figlet-core")`.

### Debug builds:

```sh
xmake f -m debug && xmake
```

In this case, the executables are in `build/<platform>/<arch>/debug/`.

### Dependencies

- GCC 16 or Clang 21 - I couldn't get Clang 22 to compile this. GCC 13 to 15 fail on the Notcurses headers; Clang 18 and Homebrew LLVM 23 are known to work.
- [Notcurses](https://github.com/dankamongmen/notcurses) (`notcurses++`) — discoverable via `pkg-config` (required only for the `ncfig` and `ncmarquee` demo tools).

## Using the Core with Other Renderers

The core FIGlet engine (`FigletFont`, `Tweening`, and `TextCanvas`) is
completely independent of Notcurses or any specific rendering library.
It has zero external dependencies and only requires the C++20 standard
library.

The core renders into a generic `TextCanvas`, which is an in-memory 2D buffer of `Cell` structures:

```cpp
struct Cell {
    char ch = ' ';
    uint32_t fg = 0xFFFFFF; // 0x00RRGGBB format

    uint8_t r() const noexcept;
    uint8_t g() const noexcept;
    uint8_t b() const noexcept;
};
```

### 1. Rendering Text to `TextCanvas`

```cpp
import nctui.figlet;
import nctui.tweening;

FigletFont font;
font.loadFromFile("fonts/banner.flf");

// Define an optional color gradient
Tweening::Gradient grad{
    .type = Tweening::GradientType::Linear,
    .orientation = Tweening::Orientation::Horizontal,
    .start = 0xff0000,
    .end = 0x0000ff
};

// Render directly into a newly created canvas sized to fit the text:
TextCanvas canvas = font.render("HELLO", grad);
```

### 2. Using with STC (`simple_term_colors`)

[STC](https://github.com/illyigan/simple_term_colors) allows streaming ANSI
escape sequences directly to `std::cout` without requiring any curses
library or TTY initialization:

```cpp
#include "stc.hpp"
import nctui.figlet;

void printWithSTC(const TextCanvas& canvas)
{
    std::cout << stc::true_color;
    for (int y = 0; y < canvas.height(); ++y) {
        for (int x = 0; x < canvas.width(); ++x) {
            const auto& cell = canvas(y, x);
            std::cout << stc::rgb_fg(cell.r(), cell.g(), cell.b()) << cell.ch;
        }
        std::cout << stc::reset << '\n';
    }
}
```

### 3. Using with ncurses (`WINDOW*`)

With classic `ncurses`, map the RGB color to an ncurses color pair and write cells using `mvwaddch`:

```cpp
#include <ncurses.h>
import nctui.figlet;

void blitToNcurses(WINDOW* win, const TextCanvas& canvas, int start_y = 0, int start_x = 0)
{
    for (int y = 0; y < canvas.height(); ++y) {
        for (int x = 0; x < canvas.width(); ++x) {
            const auto& cell = canvas(y, x);
            int pair = mapRgbToPair(cell.fg); // Custom mapping to closest init_pair
            wattron(win, COLOR_PAIR(pair));
            mvwaddch(win, start_y + y, start_x + x, cell.ch);
            wattroff(win, COLOR_PAIR(pair));
        }
    }
    wrefresh(win);
}
```

### 4. Using with Notcurses (as in `ncfig`)

Blit the `TextCanvas` cells directly to an `ncpp::Plane`:

```cpp
#include <ncpp/Plane.hh>
import nctui.figlet;

void blitToPlane(ncpp::Plane* plane, const TextCanvas& canvas, int start_y = 0, int start_x = 0)
{
    for (int y = 0; y < canvas.height(); ++y) {
        for (int x = 0; x < canvas.width(); ++x) {
            const auto& cell = canvas(y, x);
            plane->set_fg_rgb(cell.fg);
            plane->putc(start_y + y, start_x + x, cell.ch);
        }
    }
}
```

### 5. Viewport / Marquee Animations

For scrolling or sine wave marquee animations, use `renderToViewport` to
render each frame into a viewport-sized `TextCanvas`:

```cpp
TextCanvas canvas(screen_width, screen_height);
canvas.clear({' ', 0});

font.renderToViewport(
    canvas,
    y_pos,
    x_pos,
    text,
    first_gradient,
    second_gradient,
    screen_width,
    x_pos,               // offset for scrolling
    gradient_to_text,    // true: text space; false: screen space
    wave_amplitude,      // 0 for no wave
    wave_phase           // advancing angle for sine animation
);

// Then blit canvas to your target display (Notcurses, STC, ncurses, SDL, etc.)
```

## Releasing

Pushing a version tag builds the release binaries and publishes them:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

The [release workflow](.github/workflows/release.yml) runs [scripts/build-release.sh](scripts/build-release.sh) on four runners (Alpine containers for static Linux binaries, macOS Intel and Apple Silicon), collects the archives `ncfig-<arch>-<os>.tar.gz` plus `SHA256SUMS`, and creates the GitHub Release. The launcher and install scripts always fetch the latest release. Pushes to `main` and pull requests run the build jobs only.

The binaries link Notcurses statically (`xmake f --static=y`, see [xmake/static.lua](xmake/static.lua)); the script can be run locally if the static libraries of notcurses, libunistring, libdeflate and ncurses are installed.

Testing the release workflow on a fork works the same way; the launcher and install script take `NCFIG_REPO=owner/ncfig` to fetch that fork's releases.

Optionally, the tools can be offered through a Homebrew tap: create a repository `homebrew-tap` under the same GitHub account and add a repository secret `HOMEBREW_TAP_TOKEN` here, holding a token with write access to the tap (a fine-grained personal access token with "Contents: read and write" on that one repository). The workflow then renders [packaging/homebrew/ncfig.rb.in](packaging/homebrew/ncfig.rb.in) with the release checksums and pushes it to `Formula/ncfig.rb` in the tap, so `brew install <owner>/tap/ncfig` installs the new version. Without the secret, that step is skipped and the formula can be generated by hand:

```sh
scripts/homebrew-formula.sh v0.1.0 SHA256SUMS > Formula/ncfig.rb
```
