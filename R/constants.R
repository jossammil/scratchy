# Values mirror Excalidraw's packages/common/src/{constants,colors,font-metadata}.ts

.palette <- list(
  transparent = "transparent",
  black = "#1e1e1e",
  white = "#ffffff",
  gray = c("#f8f9fa", "#e9ecef", "#ced4da", "#868e96", "#343a40"),
  red = c("#fff5f5", "#ffc9c9", "#ff8787", "#fa5252", "#e03131"),
  pink = c("#fff0f6", "#fcc2d7", "#f783ac", "#e64980", "#c2255c"),
  grape = c("#f8f0fc", "#eebefa", "#da77f2", "#be4bdb", "#9c36b5"),
  violet = c("#f3f0ff", "#d0bfff", "#9775fa", "#7950f2", "#6741d9"),
  blue = c("#e7f5ff", "#a5d8ff", "#4dabf7", "#228be6", "#1971c2"),
  cyan = c("#e3fafc", "#99e9f2", "#3bc9db", "#15aabf", "#0c8599"),
  teal = c("#e6fcf5", "#96f2d7", "#38d9a9", "#12b886", "#099268"),
  green = c("#ebfbee", "#b2f2bb", "#69db7c", "#40c057", "#2f9e44"),
  yellow = c("#fff9db", "#ffec99", "#ffd43b", "#fab005", "#f08c00"),
  orange = c("#fff4e6", "#ffd8a8", "#ffa94d", "#fd7e14", "#e8590c"),
  bronze = c("#f8f1ee", "#eaddd7", "#d2bab0", "#a18072", "#846358")
)

# Hue order used for categorical chart colours.
.chart_hues <- c("blue", "red", "green", "yellow", "grape", "cyan", "orange",
                 "violet", "teal", "pink", "bronze", "gray")

.roughness <- c(architect = 0, artist = 1, cartoonist = 2)
.stroke_widths <- c(thin = 1, bold = 2, extra_bold = 4)
.fill_styles <- c("hachure", "cross-hatch", "solid", "zigzag", "dots", "dashed", "zigzag-line")
.stroke_styles <- c("solid", "dashed", "dotted")
.arrowheads <- c("arrow", "bar", "dot", "circle", "circle_outline", "triangle",
                 "triangle_outline", "diamond", "diamond_outline",
                 "cardinality_one", "cardinality_many", "cardinality_one_or_many",
                 "cardinality_exactly_one", "cardinality_zero_or_one",
                 "cardinality_zero_or_many")

.default_style <- list(
  strokeColor = "#1e1e1e",
  backgroundColor = "transparent",
  fillStyle = "solid",
  strokeWidth = 2,
  strokeStyle = "solid",
  roughness = 1,
  opacity = 100,
  fontFamily = 5,
  fontSize = 20
)

.bound_text_padding <- 5
.frame_style <- list(strokeColor = "#bbb", strokeWidth = 2, radius = 8,
                     nameFontSize = 14, nameColor = "#999999", nameOffsetY = 3)

# Fonts: Excalidraw ids and metrics, plus extra handwriting fonts bundled here.
# `id` is the Excalidraw fontFamily id (NA = not an Excalidraw font; saved as
# Excalifont with the real font recorded in customData).
.fonts <- data.frame(
  name = c("Virgil", "Helvetica", "Cascadia", "Excalifont", "Nunito", "Lilita One",
           "Comic Shanns", "Liberation Sans", "Caveat", "Patrick Hand",
           "Architects Daughter", "Gochi Hand"),
  id = c(1, 2, 3, 5, 6, 7, 8, 9, NA, NA, NA, NA),
  family = c("Virgil", "Helvetica", "Cascadia Code", "Excalifont", "Nunito", "Lilita One",
             "Comic Shanns", "Helvetica", "Caveat", "Patrick Hand",
             "Architects Daughter", "Gochi Hand"),
  units_per_em = c(1000, 2048, 2048, 1000, 1000, 1000, 1000, 2048, NA, NA, NA, NA),
  ascender = c(886, 1577, 1900, 886, 1011, 923, 750, 1854, NA, NA, NA, NA),
  descender = c(-374, -471, -480, -374, -353, -220, -250, -434, NA, NA, NA, NA),
  line_height = c(1.25, 1.15, 1.2, 1.25, 1.25, 1.15, 1.25, 1.15, 1.25, 1.25, 1.25, 1.25),
  stringsAsFactors = FALSE
)

.font_files <- list(
  "Excalifont" = c(plain = "Excalifont-Regular.ttf"),
  "Virgil" = c(plain = "Virgil.ttf"),
  "Comic Shanns" = c(plain = "ComicShanns-Regular.ttf"),
  "Nunito" = c(plain = "Nunito-Regular.ttf", bold = "Nunito-Bold.ttf"),
  "Lilita One" = c(plain = "LilitaOne-Regular.ttf"),
  "Cascadia Code" = c(plain = "CascadiaCode-Regular.ttf", bold = "CascadiaCode-Bold.ttf"),
  "Caveat" = c(plain = "Caveat-Regular.ttf", bold = "Caveat-Bold.ttf"),
  "Patrick Hand" = c(plain = "PatrickHand-Regular.ttf"),
  "Architects Daughter" = c(plain = "ArchitectsDaughter-Regular.ttf"),
  "Gochi Hand" = c(plain = "GochiHand-Regular.ttf")
)
