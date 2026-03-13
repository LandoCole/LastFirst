import Foundation

// MARK: - Bitmap Font Data

/// Bitmap glyph lookup tables for rendering text as dot patterns on the 64×64 grid.
/// Each glyph is stored as an array of UInt8 values — one per row, bits = columns (MSB = leftmost).
enum DotMatrixFonts {

    // MARK: - Large Font (7×10) for stat values

    /// 7 columns wide, 10 rows tall. Glyphs for 0-9, K, space.
    static let largeGlyphs: [Character: [UInt8]] = [
        "0": [
            0b0111110,
            0b1100011,
            0b1100011,
            0b1100111,
            0b1101011,
            0b1110011,
            0b1100011,
            0b1100011,
            0b1100011,
            0b0111110
        ],
        "1": [
            0b0001100,
            0b0011100,
            0b0101100,
            0b0001100,
            0b0001100,
            0b0001100,
            0b0001100,
            0b0001100,
            0b0001100,
            0b0111111
        ],
        "2": [
            0b0111110,
            0b1100011,
            0b0000011,
            0b0000110,
            0b0001100,
            0b0011000,
            0b0110000,
            0b1100000,
            0b1100011,
            0b1111111
        ],
        "3": [
            0b0111110,
            0b1100011,
            0b0000011,
            0b0000011,
            0b0011110,
            0b0000011,
            0b0000011,
            0b0000011,
            0b1100011,
            0b0111110
        ],
        "4": [
            0b0000110,
            0b0001110,
            0b0010110,
            0b0100110,
            0b1000110,
            0b1111111,
            0b0000110,
            0b0000110,
            0b0000110,
            0b0000110
        ],
        "5": [
            0b1111111,
            0b1100000,
            0b1100000,
            0b1111110,
            0b1100011,
            0b0000011,
            0b0000011,
            0b0000011,
            0b1100011,
            0b0111110
        ],
        "6": [
            0b0011110,
            0b0110000,
            0b1100000,
            0b1100000,
            0b1111110,
            0b1100011,
            0b1100011,
            0b1100011,
            0b1100011,
            0b0111110
        ],
        "7": [
            0b1111111,
            0b1100011,
            0b0000011,
            0b0000110,
            0b0001100,
            0b0011000,
            0b0011000,
            0b0011000,
            0b0011000,
            0b0011000
        ],
        "8": [
            0b0111110,
            0b1100011,
            0b1100011,
            0b1100011,
            0b0111110,
            0b1100011,
            0b1100011,
            0b1100011,
            0b1100011,
            0b0111110
        ],
        "9": [
            0b0111110,
            0b1100011,
            0b1100011,
            0b1100011,
            0b0111111,
            0b0000011,
            0b0000011,
            0b0000011,
            0b0000110,
            0b0111100
        ],
        "K": [
            0b1100011,
            0b1100110,
            0b1101100,
            0b1111000,
            0b1110000,
            0b1111000,
            0b1101100,
            0b1100110,
            0b1100011,
            0b1100011
        ],
        ".": [
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000,
            0b0011000,
            0b0011000
        ],
        " ": [
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000,
            0b0000000
        ]
    ]

    static let largeGlyphWidth = 7
    static let largeGlyphHeight = 10

    // MARK: - Small Font (5×7) for labels

    /// 5 columns wide, 7 rows tall. Glyphs for A-Z, 0-9, space.
    static let smallGlyphs: [Character: [UInt8]] = [
        "A": [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
        "B": [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110],
        "C": [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110],
        "D": [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110],
        "E": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
        "F": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000],
        "G": [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01110],
        "H": [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
        "I": [0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
        "J": [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100],
        "K": [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001],
        "L": [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
        "M": [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001],
        "N": [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001],
        "O": [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
        "P": [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000],
        "Q": [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101],
        "R": [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001],
        "S": [0b01110, 0b10001, 0b10000, 0b01110, 0b00001, 0b10001, 0b01110],
        "T": [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100],
        "U": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
        "V": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100],
        "W": [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001],
        "X": [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001],
        "Y": [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100],
        "Z": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111],
        "0": [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110],
        "1": [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
        "2": [0b01110, 0b10001, 0b00001, 0b00110, 0b01000, 0b10000, 0b11111],
        "3": [0b01110, 0b10001, 0b00001, 0b00110, 0b00001, 0b10001, 0b01110],
        "4": [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010],
        "5": [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110],
        "6": [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110],
        "7": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000],
        "8": [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110],
        "9": [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100],
        "'": [0b00100, 0b00100, 0b01000, 0b00000, 0b00000, 0b00000, 0b00000],
        " ": [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000]
    ]

    static let smallGlyphWidth = 5
    static let smallGlyphHeight = 7

    // MARK: - Rendering

    /// Renders a string using the specified font into an array of (col, row) lit coordinates.
    /// Glyphs are laid out left-to-right with 1-column spacing.
    /// `origin` is the top-left (col, row) of the first glyph.
    static func renderString(
        _ text: String,
        font: Font,
        origin: (col: Int, row: Int),
        gridWidth: Int = 64,
        gridHeight: Int = 64
    ) -> [(col: Int, row: Int)] {
        let glyphs: [Character: [UInt8]]
        let glyphWidth: Int

        switch font {
        case .large:
            glyphs = largeGlyphs
            glyphWidth = largeGlyphWidth
        case .small:
            glyphs = smallGlyphs
            glyphWidth = smallGlyphWidth
        }

        var litPixels: [(col: Int, row: Int)] = []
        var cursorCol = origin.col

        for char in text {
            guard let rows = glyphs[char] else { continue }

            for (rowIdx, rowBits) in rows.enumerated() {
                let pixelRow = origin.row + rowIdx
                guard pixelRow >= 0, pixelRow < gridHeight else { continue }

                for colIdx in 0..<glyphWidth {
                    let bit = (rowBits >> (glyphWidth - 1 - colIdx)) & 1
                    if bit == 1 {
                        let pixelCol = cursorCol + colIdx
                        if pixelCol >= 0, pixelCol < gridWidth {
                            litPixels.append((col: pixelCol, row: pixelRow))
                        }
                    }
                }
            }

            cursorCol += glyphWidth + 1 // 1-col spacing
        }

        return litPixels
    }

    /// Measures the width (in columns) of a string in the given font, including inter-glyph spacing.
    static func measureWidth(_ text: String, font: Font) -> Int {
        let glyphWidth = font == .large ? largeGlyphWidth : smallGlyphWidth
        let charCount = text.count
        guard charCount > 0 else { return 0 }
        return charCount * glyphWidth + (charCount - 1) // 1-col spacing between glyphs
    }

    enum Font {
        case large
        case small
    }
}
