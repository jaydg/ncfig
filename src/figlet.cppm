module;

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

export module nctui.figlet;

export import nctui.canvas;
import nctui.tweening;

export class FigletFont
{
public:
    FigletFont() = default;

    /**
     * @brief Resolves the font given on the command line to a file.
     *
     * @param spec A path to a .flf file, or the name of a font (with or without
     *             the .flf extension) to look up in the font directories.
     * @return The path of the font file, or an empty string if none was found.
     *
     * The font directories are, in this order: $NCFIG_FONTDIR, fonts/ next to
     * the executable, and ../share/ncfig/fonts relative to the executable
     * (where installed releases keep the fonts). A name is looked up there
     * first and in the working directory last, so a stray file doesn't shadow
     * a shipped font; use ./name.flf for a file in the working directory.
     */
    static std::string findFont(const std::string& spec)
    {
        namespace fs = std::filesystem;

        std::vector<fs::path> candidates;

        if (isFontName(spec)) {
            for (const auto& dir : fontDirs()) {
                candidates.push_back(dir / spec);
                candidates.push_back(dir / (spec + ".flf"));
            }
        }

        candidates.emplace_back(spec);
        candidates.emplace_back(spec + ".flf");

        for (const auto& candidate : candidates) {
            std::error_code ec;

            if (fs::is_regular_file(candidate, ec)) {
                return candidate.string();
            }
        }

        return "";
    }

    /**
     * @brief Whether a font specification is a name (no directory part) rather than a path.
     */
    static bool isFontName(const std::string& spec)
    {
        return std::filesystem::path(spec).filename() == std::filesystem::path(spec);
    }

    /**
     * @brief The directories in which findFont() looks for fonts given by name.
     */
    static std::vector<std::filesystem::path> fontDirs()
    {
        std::vector<std::filesystem::path> dirs;

        if (const char* env = std::getenv("NCFIG_FONTDIR"); env && *env) {
            dirs.emplace_back(env);
        }

        auto exe = executableDir();

        if (!exe.empty()) {
            dirs.push_back(exe / "fonts");
            dirs.push_back(exe.parent_path() / "share" / "ncfig" / "fonts");
        }

        return dirs;
    }

    /**
     * @brief Loads and parses a standard FIGlet font (.flf) file.
     *
     * @param filename Path to the .flf file.
     * @return true if successfully loaded and parsed, false otherwise.
     */
    bool loadFromFile(const std::string& filename)
    {
        std::ifstream file(filename, std::ios::in);

        if (!file.is_open()) {
            return false;
        }

        std::string header;

        if (!std::getline(file, header)) {
            return false;
        }

        std::istringstream iss(header);
        std::string magic;
        iss >> magic;

        // FIGlet header signatures always start with "flf2a"
        if (magic.size() < 6 || magic.substr(0, 5) != "flf2a") {
            return false;
        }

        // The 6th character indicates the custom hardblank character (often '$')
        hardblank = magic[5];

        if (!(iss >> height >> baseline >> max_length >> old_layout >> comment_lines)) {
            return false;
        }

        // Skip any comment lines at the beginning of the file
        for (int i = 0; i < comment_lines; ++i) {
            std::string dummy;

            if (!std::getline(file, dummy)) {
                return false;
            }
        }

        char32_t endmark = U'\0';
        bool endmark_set = false;
        char32_t hb = static_cast<unsigned char>(hardblank);

        auto parseGlyphRow = [&](std::string line) -> std::u32string {
            if (!line.empty() && line.back() == '\r')
            {
                line.pop_back();
            }

            std::u32string u32line = decodeUtf8(line);

            // Detect the endmark character from the end of the very first line
            if (!endmark_set && !u32line.empty())
            {
                endmark = u32line.back();
                endmark_set = true;
            }

            // FIGlet lines end with either 1 endmark, or 2 endmarks on the final glyph line
            if (!u32line.empty() && u32line.back() == endmark)
            {
                u32line.pop_back();
            }

            if (!u32line.empty() && u32line.back() == endmark)
            {
                u32line.pop_back();
            }

            // Replace custom hardblanks with space characters
            for (char32_t& ch : u32line)
            {
                if (ch == hb) {
                    ch = U' ';
                }
            }

            return u32line;
        };

        // 1. Parse standard printable ASCII characters (characters 32 to 126)
        for (char32_t code = 32; code <= 126; ++code) {
            std::vector<std::u32string> glyph_rows;

            for (int r = 0; r < height; ++r) {
                std::string line;

                if (!std::getline(file, line)) {
                    return false;
                }

                glyph_rows.push_back(parseGlyphRow(std::move(line)));
            }

            glyphs[code] = std::move(glyph_rows);
        }

        // 2. Check for the 7 standard un-tagged German characters (Ä, Ö, Ü, ä, ö, ü, ß)
        // or code-tagged extended characters
        std::string pending_code_line;
        std::string first_post_ascii;

        while (std::getline(file, first_post_ascii)) {
            if (!first_post_ascii.empty() && first_post_ascii.back() == '\r') {
                first_post_ascii.pop_back();
            }

            if (!first_post_ascii.empty()) {
                break;
            }
        }

        if (!first_post_ascii.empty()) {
            std::u32string u32first = decodeUtf8(first_post_ascii);

            if (endmark_set && u32first.back() == endmark) {
                constexpr char32_t deutsch_codes[7] = {196, 214, 220, 228, 246, 252, 223};

                for (int d = 0; d < 7; ++d) {
                    std::vector<std::u32string> glyph_rows;
                    bool ok = true;

                    for (int r = 0; r < height; ++r) {
                        std::string line;

                        if (d == 0 && r == 0) {
                            line = first_post_ascii;
                        } else if (!std::getline(file, line)) {
                            ok = false;
                            break;
                        }

                        glyph_rows.push_back(parseGlyphRow(std::move(line)));
                    }

                    if (!ok) {
                        break;
                    }

                    glyphs[deutsch_codes[d]] = std::move(glyph_rows);
                }
            } else {
                pending_code_line = first_post_ascii;
            }
        }

        // 3. Parse any extra/extended code-tagged Unicode characters present in the font file
        std::string code_line;

        while (true) {
            if (!pending_code_line.empty()) {
                code_line = std::move(pending_code_line);
                pending_code_line.clear();
            } else if (!std::getline(file, code_line)) {
                break;
            }

            if (!code_line.empty() && code_line.back() == '\r') {
                code_line.pop_back();
            }

            if (code_line.empty()) {
                continue;
            }

            std::istringstream code_iss(code_line);
            std::string code_str;
            code_iss >> code_str;

            if (code_str.empty()) {
                continue;
            }

            char32_t code = 0;

            try {
                // Negative code tags are not standard Unicode codepoints; skip their glyph lines
                if (code_str[0] == '-') {
                    for (int r = 0; r < height; ++r) {
                        std::string dummy;
                        std::getline(file, dummy);
                    }

                    continue;
                }

                // Handle hex (0x), octal (0), and base-10 indices
                if (code_str.size() > 2 && code_str[0] == '0' && (code_str[1] == 'x' || code_str[1] == 'X')) {
                    code = std::stoul(code_str, nullptr, 16);
                } else if (code_str.size() > 1 && code_str[0] == '0') {
                    code = std::stoul(code_str, nullptr, 8);
                } else {
                    code = std::stoul(code_str, nullptr, 10);
                }
            } catch (...) {
                continue; // Skip invalid blocks or malformed rows
            }

            std::vector<std::u32string> glyph_rows;
            bool success = true;

            for (int r = 0; r < height; ++r) {
                std::string line;

                if (!std::getline(file, line)) {
                    success = false;
                    break;
                }

                glyph_rows.push_back(parseGlyphRow(std::move(line)));
            }

            if (!success) {
                break;
            }

            glyphs[code] = std::move(glyph_rows);
        }

        return true;
    }

    /**
     * @brief Renders text onto a TextCanvas at the specified (y, x) coordinates.
     *
     * @param canvas The target TextCanvas.
     * @param y Top-left Y row coordinate.
     * @param x Top-left X column coordinate.
     * @param text String view containing UTF-8 input text.
     * @param first First gradient for the text.
     * @param second Second gradient for the text.
     */
    void render(
        TextCanvas& canvas,
        int y,
        int x,
        std::string_view text,
        Tweening::Gradient first = {},
        Tweening::Gradient second = {}
    ) const
    {
        if (height <= 0) {
            return;
        }

        updateTextCache(text);
        const auto& lines = text_cache_lines;
        auto[
            one_d,
            two_d,
            max_width
        ] = prepareGradients(lines, first, second);

        for (int i = 0; i < (int)lines.size(); ++i) {
            if (!two_d.empty()) {
                // 2d tweening
                // print by character
                for (int j = 0; j < (int)lines[i].size(); ++j) {
                    canvas.set(y + i, x + j, lines[i][j], two_d[i][j]);
                }
            } else if (!one_d.empty() && first.orientation == Tweening::Orientation::Vertical) {
                for (int j = 0; j < (int)lines[i].size(); ++j) {
                    canvas.set(y + i, x + j, lines[i][j], one_d[i]);
                }
            } else if (!one_d.empty() && first.orientation == Tweening::Orientation::Horizontal) {
                // print by character
                for (int j = 0; j < (int)lines[i].size(); ++j) {
                    canvas.set(y + i, x + j, lines[i][j], one_d[j]);
                }
            } else {
                for (int j = 0; j < (int)lines[i].size(); ++j) {
                    canvas.set(y + i, x + j, lines[i][j], 0xFFFFFF);
                }
            }
        }
    }

    /**
     * @brief Renders text into a newly created TextCanvas sized exactly to fit the text.
     *
     * @param text String view containing UTF-8 input text.
     * @param first First gradient for the text.
     * @param second Second gradient for the text.
     * @return A TextCanvas containing the rendered text and colors.
     */
    TextCanvas render(
        std::string_view text,
        Tweening::Gradient first = {},
        Tweening::Gradient second = {}
    ) const
    {
        if (height <= 0) {
            return {};
        }

        updateTextCache(text);
        const auto& lines = text_cache_lines;
        int text_width = text_cache_width;
        int text_height = static_cast<int>(lines.size());

        TextCanvas canvas(text_width, text_height);
        render(canvas, 0, 0, text, first, second);
        return canvas;
    }

    /**
     * @brief Renders a portion of text onto a TextCanvas with gradients applied to viewport or text dimensions.
     *
     * This is useful for marquee-style rendering where text scrolls across a fixed viewport.
     *
     * @param canvas The target TextCanvas.
     * @param y Top-left Y row coordinate.
     * @param text String view containing UTF-8 input text.
     * @param first First gradient for the text.
     * @param second Second gradient for the text.
     * @param viewport_width Width of the viewport (defaults to canvas.width() if <= 0).
     * @param offset Horizontal offset into the text (for scrolling).
     * @param use_text_dimensions If true, use text dimensions for gradients; otherwise use viewport width x text height.
     * @param wave_amplitude Amplitude of the wave effect (default 0).
     * @param wave_phase Phase of the wave effect (default 0.0f).
     */
    void renderToViewport(
        TextCanvas& canvas,
        int y,
        std::string_view text,
        Tweening::Gradient& first,
        Tweening::Gradient& second,
        int viewport_width = 0,
        int offset = 0,
        bool use_text_dimensions = false,
        int wave_amplitude = 0,
        float wave_phase = 0.0f
    ) const
    {
        if (height <= 0) {
            return;
        }

        updateTextCache(text);
        const auto& lines = text_cache_lines;

        if (lines.empty()) {
            return;
        }

        if (viewport_width <= 0) {
            viewport_width = canvas.width();
        }

        int text_height = static_cast<int>(lines.size());
        int text_width = text_cache_width;

        // Prepare gradients
        // If use_text_dimensions, use text dimensions; otherwise use viewport width x text height
        int gradient_width = use_text_dimensions ? text_width : viewport_width;
        int gradient_height = text_height + 2 * wave_amplitude;

        if (first.type == Tweening::GradientType::Linear
                && second.type == Tweening::GradientType::Linear) {
            // Parallel gradients
            first.steps = gradient_height;
            second.steps = gradient_width;
        } else if (first.type == Tweening::GradientType::Radial) {
            first.width = gradient_width;
            first.height = gradient_height;
        } else if (first.type == Tweening::GradientType::Linear
                   && first.orientation == Tweening::Orientation::Vertical) {
            // Vertical: steps = gradient height
            first.steps = gradient_height;
        } else if (first.type == Tweening::GradientType::Linear
                   && first.orientation == Tweening::Orientation::Horizontal) {
            // Horizontal: steps = gradient width
            first.steps = gradient_width;
        }

        auto[one_d, two_d, max_width] = prepareGradients(lines, first, second);

        int canvas_height = canvas.height();

        // Map every text column → its character's center x (in text coordinates).
        // Snapping per-column y to the character center keeps each glyph internally
        // coherent during wave rendering (all columns of one glyph share one y offset).
        const auto& col_center = text_cache_col_center;

        int line_offset = 0;
        int visible_width = 0;

        if (offset < viewport_width && offset + text_width > 0) {
            line_offset = std::max(0, -offset);
            visible_width = std::min(text_width - line_offset, viewport_width - std::max(0, offset));
        }

        if (visible_width <= 0) {
            return;
        }

        int screen_x = std::max(0, offset);

        // Outer loop over columns so y_off (and the sin() it needs) is computed
        // once per column rather than once per (row, column) pair.
        for (int j = 0; j < visible_width; ++j) {
            int text_x = line_offset + j;
            int screen_j = screen_x + j;

            // Compute wave y-offset for this column (0 when wave_amplitude == 0).
            // Wave always uses screen-space position,
            // i. e. circular instances share one continuous wave
            int y_off = 0;

            if (wave_amplitude != 0 && text_x < (int)col_center.size()) {
                constexpr float wave_spatial_freq = 2.0f * 3.14159265f / 150.0f;
                float char_x = static_cast<float>(offset) + col_center[text_x];
                float phase = wave_phase + char_x * wave_spatial_freq;
                y_off = static_cast<int>(std::round(wave_amplitude * std::sin(phase)));
            }

            int col_y = std::clamp(y + y_off, 0, std::max(0, canvas_height - text_height));
            int color_x = use_text_dimensions ? text_x : screen_j;

            for (int i = 0; i < text_height; ++i) {
                if (text_x >= (int)lines[i].size()) {
                    break;
                }

                if (col_y + i >= canvas_height) {
                    continue;
                }

                // Get color based on position.
                // color_y shifts with the wave so colors follow the character's screen position.
                uint32_t color = 0xFFFFFF;
                int color_y = wave_amplitude + y_off + i;

                if (color_y < (int)two_d.size() && color_x < (int)two_d[color_y].size()) {
                    color = two_d[color_y][color_x];
                } else if (first.orientation == Tweening::Orientation::Vertical
                           && color_y < (int)one_d.size()) {
                    color = one_d[color_y];
                } else if ((first.orientation == Tweening::Orientation::Horizontal
                            || (first.type == Tweening::GradientType::Linear && second.type == Tweening::GradientType::Linear))
                           && color_x < (int)one_d.size()) {
                    color = one_d[color_x];
                }

                canvas.set(col_y + i, screen_j, lines[i][text_x], color);
            }
        }
    }

    int getHeight() const
    {
        return height;
    }

    /**
     * @brief Returns the dimensions of rendered text.
     * @param text String view containing UTF-8 input text.
     * @return A pair of (width, height) in columns and rows.
     */
    std::pair<int, int> getTextDimensions(std::string_view text) const
    {
        if (height <= 0) {
            return {0, 0};
        }

        updateTextCache(text);

        if (text_cache_lines.empty()) {
            return {0, 0};
        }

        return {text_cache_width, static_cast<int>(text_cache_lines.size())};
    }

private:
    /**
     * @brief The directory containing the running executable, or an empty path.
     */
    static std::filesystem::path executableDir()
    {
        namespace fs = std::filesystem;
        std::error_code ec;
#ifdef __APPLE__
        uint32_t size = 0;
        _NSGetExecutablePath(nullptr, &size);
        std::string buffer(size, '\0');

        if (_NSGetExecutablePath(buffer.data(), &size) != 0) {
            return {};
        }

        buffer.resize(std::strlen(buffer.c_str()));
        auto exe = fs::canonical(buffer, ec);
#else
        auto exe = fs::read_symlink("/proc/self/exe", ec);
#endif

        if (ec) {
            return {};
        }

        return exe.parent_path();
    }
    char hardblank = '$';
    int height = 0;
    int baseline = 0;
    int max_length = 0;
    int old_layout = 0;
    int comment_lines = 0;

    std::unordered_map<char32_t, std::vector<std::u32string>> glyphs;

    mutable std::string text_cache_key;
    mutable std::vector<std::u32string> text_cache_lines;
    mutable int text_cache_width = 0;
    mutable std::vector<std::pair<int, int>> text_cache_char_ranges;
    mutable std::vector<float> text_cache_col_center;

    void updateTextCache(std::string_view text) const
    {
        if (text_cache_key == text) {
            return;
        }

        text_cache_key.assign(text);
        text_cache_lines = renderToStrings(text);
        text_cache_width = 0;

        for (const auto& line : text_cache_lines) {
            text_cache_width = std::max(text_cache_width, static_cast<int>(line.size()));
        }

        text_cache_char_ranges = buildCharRanges(text);
        text_cache_col_center.assign(text_cache_width, 0.0f);

        for (const auto& [s, e] : text_cache_char_ranges) {
            float center = (s + e - 1) * 0.5f;

            for (int c = s; c < e && c < text_cache_width; ++c) {
                text_cache_col_center[c] = center;
            }
        }
    }

    // Simple robust custom UTF-8 state decoder helper loop
    static std::u32string decodeUtf8(std::string_view text)
    {
        std::u32string codepoints;
        size_t i = 0;

        while (i < text.size()) {
            unsigned char c = text[i];
            char32_t cp = 0;
            size_t bytes = 0;

            if (c <= 0x7F) {
                cp = c;
                bytes = 1;
            } else if ((c & 0xE0) == 0xC0) {
                cp = c & 0x1F;
                bytes = 2;
            } else if ((c & 0xF0) == 0xE0) {
                cp = c & 0x0F;
                bytes = 3;
            } else if ((c & 0xF8) == 0xF0) {
                cp = c & 0x07;
                bytes = 4;
            } else {
                cp = c;
                bytes = 1;
            }

            if (i + bytes <= text.size()) {
                for (size_t b = 1; b < bytes; ++b) {
                    cp = (cp << 6) | (static_cast<unsigned char>(text[i + b]) & 0x3F);
                }

                i += bytes;
            } else {
                cp = c;
                i += 1;
            }

            codepoints.push_back(cp);
        }

        return codepoints;
    }

    // Returns {start_col, end_col} for every character in the rendered text.
    std::vector<std::pair<int, int>> buildCharRanges(std::string_view sv) const
    {
        std::vector<std::pair<int, int>> ranges;
        auto codepoints = decodeUtf8(sv);
        int x = 0;

        for (char32_t cp : codepoints) {
            int w = 0;
            auto it = glyphs.find(cp);

            if (it != glyphs.end() && !it->second.empty()) {
                w = static_cast<int>(it->second[0].size());
            } else {
                auto space_it = glyphs.find(U' ');

                if (space_it != glyphs.end() && !space_it->second.empty()) {
                    w = static_cast<int>(space_it->second[0].size());
                }
            }

            ranges.push_back({x, x + w});
            x += w;
        }

        return ranges;
    }

    std::vector<std::u32string> renderToStrings(const std::string_view text, bool append_nl = false) const
    {
        std::vector<std::u32string> ret;

        // Decode UTF-8 code units to UTF-32 code points for font matching
        std::u32string codepoints = decodeUtf8(text);

        // Process the string slice line by line
        for (int r = 0; r < height; ++r) {
            std::u32string line;

            for (char32_t cp : codepoints) {
                auto it = glyphs.find(cp);

                if (it != glyphs.end() && r < (int)it->second.size()) {
                    line += it->second[r];
                } else {
                    // Fallback to a space glyph if a character is missing
                    auto space_it = glyphs.find(U' ');

                    if (space_it != glyphs.end() && r < (int)space_it->second.size()) {
                        line += space_it->second[r];
                    }
                }
            }

            if (append_nl) {
                line += U'\n';
            }

            ret.emplace_back(line);
        }

        return ret;
    }

    /**
     * @brief Prepares the gradients and colors for rendering, caching results in the gradient objects.
     *
     * On first call the gradient is computed and stored in first.one_d / first.two_d.
     * Subsequent calls with the same dimensions reuse the cached result without recomputing.
     * The cache is invalidated automatically when the expected gradient dimensions change
     * (e.g. on terminal resize).
     *
     * @param lines The lines of text (used to derive default dimensions).
     * @param first Primary gradient — result is cached here.
     * @param second Secondary gradient (used for parallel 2-D gradients).
     * @return Const references to the cached one_d / two_d inside first, plus max_width.
     */
    std::tuple <
    const std::vector<uint32_t>&,
          const std::vector<std::vector<uint32_t>>&,
          std::size_t
          > prepareGradients(
              const std::vector<std::u32string>& lines,
              Tweening::Gradient& first,
              Tweening::Gradient& second
          ) const
    {
        std::size_t max_width = 0;

        for (const auto& line : lines) {
            max_width = std::max(max_width, line.size());
        }

        if (first.type == Tweening::GradientType::Linear
                && second.type == Tweening::GradientType::Linear) {
            // this combination is only supported for parallel linear
            // gradients, so we can ignore orientation
            if (first.steps == 0) {
                first.steps = lines.size();
            }

            if (second.steps == 0) {
                second.steps = max_width;
            }

            if (first.two_d.size() != first.steps
                    || first.two_d.empty()
                    || first.two_d[0].size() != second.steps) {
                first.two_d = Tweening::Parallel(first, second);
                first.one_d.clear();
            }
        } else if (first.type == Tweening::GradientType::Radial) {
            // Radial gradient
            if (first.width == 0) {
                first.width = max_width;
            }

            if (first.height == 0) {
                first.height = lines.size();
            }

            if (first.two_d.size() != first.height
                    || first.two_d.empty()
                    || first.two_d[0].size() != first.width) {
                first.two_d = Tweening::radial(first);
                first.one_d.clear();
            }
        } else if (first.type == Tweening::GradientType::Linear
                   && first.orientation == Tweening::Orientation::Vertical) {
            // One-dimensional gradient (vertical)
            if (first.steps == 0) {
                first.steps = lines.size();
            }

            if (first.one_d.size() != first.steps) {
                first.one_d = Tweening::Linear(first);
                first.two_d.clear();
            }
        } else if (first.type == Tweening::GradientType::Linear
                   && first.orientation == Tweening::Orientation::Horizontal) {
            // One-dimensional gradient (horizontal)
            if (first.steps == 0) {
                first.steps = max_width;
            }

            if (first.one_d.size() != first.steps) {
                first.one_d = Tweening::Linear(first);
                first.two_d.clear();
            }
        }

        return {first.one_d, first.two_d, max_width};
    }
};
