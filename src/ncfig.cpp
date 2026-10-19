#include <ncpp/NotCurses.hh>
#include <ncpp/Plane.hh>

#include <iostream>
#include <string>
#include <string_view>

// set by the version rule in xmake.lua
#ifndef NCFIG_VERSION
#define NCFIG_VERSION "unknown"
#endif

using namespace std::string_view_literals;

import nctui.cmdline;
import nctui.figlet;
import nctui.tweening;

auto help = "Usage: ncfig -f <font> [-v <gradient>] [-r <gradient>] [-h <gradient>] [text]\n"
            "\n"
            "  -f <font>      : Font file (.flf), or the name of a font in $NCFIG_FONTDIR\n"
            "                   or in the fonts directory shipped with ncfig\n"
            "  -v <gradient>  : Specify the vertical color gradient\n"
            "  -h <gradient>  : Specify the horizontal color gradient\n"
            "  -r <gradient>  : Specify the radial color gradient\n"
            "  text           : The text to render\n"
            "  --version      : Print the version and exit\n"
            "\n"
            "Gradients are specified as pairs of hexadecimal colors, e.g.\n"
            "0xff0000:0x00ff00 for a red-to-green gradient. They can optionally have a center\n"
            "color, e.g. 0xff0000:0x00ff00:0x0000ff for a red-to-green-to-blue gradient.\n"
            "\n"
            "Linear and vertical gradients can be combined (the two colors\n"
            "will be added together); radial gradients are exclusive.\n"sv;

int main(int argc, char** argv)
{
    CmdLine opts(argc, argv);

    if (opts.cmdOptionExists("-?") || opts.cmdOptionExists("--help")) {
        std::cout << help;

        return EXIT_SUCCESS;
    }

    if (opts.cmdOptionExists("--version")) {
        std::cout << "ncfig " NCFIG_VERSION "\n";

        return EXIT_SUCCESS;
    }

    std::string filename = opts.getCmdOption("-f");

    // Validate gradient options
    if (!opts.validateGradients()) {
        std::cerr << "Error: radial and vertical gradients cannot be combined.\n";
        std::cout << help;

        return EXIT_FAILURE;
    }

    // Get gradients from command line options
    auto[first, second] = opts.getGradients();

    // Get the text to display
    std::string text = opts.getText();

    if (text.empty()) {
        text = "HELLO NOTCURSES!";
    }

    if (filename.empty()) {
        std::cout << help;

        return EXIT_FAILURE;
    }

    std::string fontfile = FigletFont::findFont(filename);

    if (fontfile.empty()) {
        std::cerr << "Font not found: " << filename << "\n";

        if (FigletFont::isFontName(filename)) {
            std::cerr << "Font directories searched for names:\n";

            for (const auto& dir : FigletFont::fontDirs()) {
                std::cerr << "  " << dir.string() << "\n";
            }
        }

        return EXIT_FAILURE;
    }

    FigletFont font;

    if (!font.loadFromFile(fontfile)) {
        std::cerr << "Failed to parse font file " << fontfile << ".\n";

        return EXIT_FAILURE;
    }

    notcurses_options options{};
    options.flags = NCOPTION_SUPPRESS_BANNERS | NCOPTION_CLI_MODE;

    auto nc = ncpp::NotCurses(options);
    ncpp::Plane* std_plane = nc.get_stdplane();

    // Render to generic TextCanvas, then blit to Notcurses plane
    TextCanvas canvas = font.render(text, first, second);

    int max_x = std::min(canvas.width(), static_cast<int>(std_plane->get_dim_x()));

    std_plane->putstr("\n");

    for (int y = 0; y < canvas.height(); ++y) {
        for (int x = 0; x < max_x; ++x) {
            const auto& cell = canvas(y, x);
            std_plane->set_fg_rgb(cell.fg);
            std_plane->putwch(static_cast<wchar_t>(cell.ch));
        }

        std_plane->putstr("\n");
    }

    nc.render();

    return EXIT_SUCCESS;
}
