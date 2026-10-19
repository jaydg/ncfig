#include <ncpp/NotCurses.hh>
#include <ncpp/Plane.hh>
#include <ncpp/NCKey.hh>

#include <chrono>
#include <cmath>
#include <iostream>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

using namespace std::string_view_literals;
using namespace std::chrono_literals;

import nctui.cmdline;
import nctui.figlet;
import nctui.tweening;

auto help = "Usage: ncmarquee -f <font> [-v <gradient>] [-h <gradient>] [-r <gradient>]\n"
            "                           [-s <ms>] [-t] [-c] [-w <amplitude>] [text]\n"
            "\n"
            "  -f <font>      : Font file (.flf), or the name of a font in $NCFIG_FONTDIR\n"
            "                   or in the fonts directory shipped with ncfig\n"
            "  -v <gradient>  : Specify the vertical color gradient\n"
            "  -h <gradient>  : Specify the horizontal color gradient\n"
            "  -r <gradient>  : Specify the radial color gradient\n"
            "  -s <ms>        : Scroll speed in milliseconds (default: 50)\n"
            "  -t             : Apply gradient to text dimensions\n"
            "                   (default: apply to the visible area of the text)\n"
            "  -c             : Circular mode (text is directly followed by itself)\n"
            "  -w <amplitude> : Sine wave vertical movement with the given amplitude in rows\n"
            "  text           : The text to render (default: HELLO NOTCURSES!)\n"
            "\n"
            "Gradients are specified as pairs of hexadecimal colors, e.g.\n"
            "0xff0000:0x00ff00 for a red-to-green gradient. They can optionally have a center\n"
            "color, e.g. 0xff0000:0x00ff00:0x0000ff for a red-to-green-to-blue gradient.\n"
            "\n"
            "Linear and vertical gradients can be combined (the two colors\n"
            "will be added together); radial gradients are exclusive.\n"
            "\n"
            "Creates a full-screen marquee animation. Press any key to exit.\n"sv;

int main(int argc, char** argv)
{
    CmdLine opts(argc, argv);

    if (opts.cmdOptionExists("-?") || opts.cmdOptionExists("--help")) {
        std::cout << help;

        return EXIT_SUCCESS;
    }

    std::string filename = opts.getCmdOption("-f");

    // Validate gradient options
    if (!opts.validateGradients()) {
        std::cerr << "Error: radial and vertical gradients cannot be combined.\n";
        std::cout << help;

        return EXIT_FAILURE;
    }

    // Parse speed option (default: 50ms)
    int delay_ms = 50;
    std::string speed_str = opts.getCmdOption("-s");

    if (!speed_str.empty()) {
        try {
            delay_ms = std::stoi(speed_str);
        } catch (...) {
            std::cerr << "Error: Invalid speed value. Must be an integer.\n";
            std::cout << help;

            return EXIT_FAILURE;
        }
    }

    // Check if gradient should be applied to text dimensions
    bool gradient_to_text = opts.cmdOptionExists("-t");

    // Check if circular mode is enabled
    bool circular_mode = opts.cmdOptionExists("-c");

    // Parse wave amplitude option (0 = disabled)
    int wave_amplitude = 0;
    std::string wave_str = opts.getCmdOption("-w");

    if (!wave_str.empty()) {
        try {
            wave_amplitude = std::stoi(wave_str);
        } catch (...) {
            std::cerr << "Error: Invalid wave amplitude. Must be an integer.\n";
            std::cout << help;

            return EXIT_FAILURE;
        }
    }

    // Get gradients from command line options
    auto[first, second] = opts.getGradients();

    // Get the text to display
    std::string text = opts.getText();

    if (text.empty()) {
        text = "HELLO NOTCURSES!";
    }

    // In circular mode, add a space to ensure separation between instances
    if (circular_mode) {
        text += ' ';
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

    // Initialize NotCurses in full-screen mode (not CLI mode)
    notcurses_options nc_opts{};
    nc_opts.flags = NCOPTION_SUPPRESS_BANNERS;
    auto nc = ncpp::NotCurses(nc_opts);
    ncpp::Plane* std_plane = nc.get_stdplane();

    // Get the standard plane dimensions
    int screen_width = std_plane->get_dim_x();
    int screen_height = std_plane->get_dim_y();

    // Get the dimensions of the rendered text
    auto[text_width, text_height] = font.getTextDimensions(text);

    if (text_width == 0 || text_height == 0) {
        std::cerr << "Failed to render text or text has no dimensions.\n";

        return EXIT_FAILURE;
    }

    // Calculate vertical position to center the text
    int y_pos = (screen_height - text_height) / 2;

    // Position for marquee animation
    // In both modes, x_pos is where the text's x=0 (first character) is rendered
    // Start just off-screen to the right
    int x_pos = screen_width;

    // Animation loop
    bool running = true;

    // Angular step per frame: 2π / 120 gives a ~6-second cycle at 50ms/frame
    constexpr float wave_step = 2.0f * static_cast<float>(M_PI) / 120.0f;
    constexpr float wave_period = 2.0f * static_cast<float>(M_PI);
    float wave_phase = 0.0f;

    // In-memory frame buffer independent of Notcurses
    TextCanvas canvas(screen_width, screen_height);

    while (running) {
        // Clear canvas and Notcurses plane
        canvas.clear({U' ', 0});
        std_plane->erase();

        if (circular_mode) {
            // In circular mode, x_pos is where the first instance's x=0 is rendered
            // Render that instance
            font.renderToViewport(
                canvas,
                y_pos,
                text,
                first,
                second,
                screen_width,
                x_pos,
                gradient_to_text,
                wave_amplitude,
                wave_phase
            );

            // Render additional instances to the right if they fit within viewport
            for (int offset = x_pos + text_width; offset < screen_width; offset += text_width) {
                font.renderToViewport(
                    canvas,
                    y_pos,
                    text,
                    first,
                    second,
                    screen_width,
                    offset,
                    gradient_to_text,
                    wave_amplitude,
                    wave_phase
                );
            }

        } else {
            // Normal mode: render once
            font.renderToViewport(
                canvas,
                y_pos,
                text,
                first,
                second,
                screen_width,
                x_pos,
                gradient_to_text,
                wave_amplitude,
                wave_phase
            );
        }

        // Blit TextCanvas to Notcurses plane
        for (int y = 0; y < canvas.height(); ++y) {
            for (int x = 0; x < canvas.width(); ++x) {
                const auto& cell = canvas(y, x);

                if (cell.ch != U' ' && cell.ch != U'\u2800') {
                    std_plane->set_fg_rgb(cell.fg);
                    std_plane->putwch(y, x, static_cast<wchar_t>(cell.ch));
                }
            }
        }

        // Render the frame
        nc.render();

        // Move the text to the left
        x_pos--;

        if (circular_mode) {
            // Wrap x_pos within one text period to keep sin() arguments bounded.
            // Visual continuity is preserved because rendering handles arbitrary offsets.
            if (x_pos <= -text_width) {
                x_pos += text_width;
            }
        } else {
            // In normal mode, reset when text has completely left the visible area
            if (x_pos + text_width <= 0) {
                x_pos = screen_width;
            }
        }

        // Check for key press (non-blocking)
        ncinput input{};
        uint32_t key = nc.get(false, &input);

        // Check if a key was pressed (any key except timeout/none)
        // In non-blocking mode, get returns 0 on timeout.
        // Terminals with the kitty keyboard protocol also report key releases
        // and repeats; the release of the Enter that started us must not quit.
        if (key != 0 && (input.evtype == NCTYPE_PRESS || input.evtype == NCTYPE_UNKNOWN)) {
            running = false;
        }

        wave_phase += wave_step;

        if (wave_phase >= wave_period) {
            wave_phase -= wave_period;
        }

        // Add delay between frames
        std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
    }

    return EXIT_SUCCESS;
}
