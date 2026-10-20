# Figures for README.md (man/figures). Run from the package root:
#   Rscript data-raw/readme-figures.R
# studio.jpg and slide-*.png are screenshots of the app and of the demo deck.
devtools::load_all(quiet = TRUE)
library(ggplot2)
out <- "man/figures"

cars <- ggplot(mpg, aes(class)) + geom_bar(fill = "#a5d8ff") +
  labs(title = "What do people drive?", x = NULL, y = "cars") + theme_excalidraw(grid = "y")

hero <- as_excalidraw(cars, theme = NULL, width = 820, height = 480) |>
  exc_mark(x = "suv", y = c(0, 62), type = "box") |>
  exc_note("SUVs win!", x = "midsize", y = 52, to = c("suv", 50)) |>
  exc_callout("only 5 of these", x = "2seater", y = 5, dx = 30, dy = -70)
exc_save(hero, file.path(out, "hero.png"), scale = 1.5)

tile <- function(scene, file) exc_save(scene, file, scale = 1)
econ <- subset(economics, date > as.Date("2005-01-01"))
plots <- list(
  stacked = ggplot(mpg, aes(class, fill = drv)) + geom_bar() + scale_fill_excalidraw() +
    coord_flip() + labs(title = "Drive train by class", x = NULL),
  line = ggplot(econ, aes(date, unemploy / 1000)) + geom_line(linewidth = 1, colour = "#1971c2") +
    labs(title = "Unemployment (millions)", x = NULL, y = NULL),
  scatter = ggplot(mpg, aes(displ, hwy, colour = drv)) + geom_point(size = 2.5) +
    scale_colour_excalidraw() + labs(title = "Bigger engines, fewer miles"),
  boxplot = ggplot(mpg, aes(drv, hwy, fill = drv)) + geom_boxplot(show.legend = FALSE) +
    scale_fill_excalidraw() + labs(title = "Highway mpg"),
  histogram = ggplot(faithful, aes(eruptions)) + geom_histogram(bins = 20, fill = "#ffec99") +
    labs(title = "Old Faithful"),
  pie = ggplot(data.frame(f = c("ink", "paper", "coffee"), n = c(3, 5, 2)), aes("", n, fill = f)) +
    geom_col(width = 1) + coord_polar("y") + scale_fill_excalidraw() +
    theme_void(base_family = "Excalifont", base_size = 15) + labs(title = "What sketching takes", fill = NULL)
)
files <- character()
for (nm in names(plots)) {
  f <- file.path(tempdir(), paste0(nm, ".png"))
  theme <- if (nm == "pie") NULL else theme_excalidraw()
  tile(as_excalidraw(plots[[nm]], theme = theme, width = 600, height = 400), f)
  files <- c(files, f)
}
presets <- c("xkcd", "blueprint", "chalkboard", "pencil")
for (pr in presets) {
  f <- file.path(tempdir(), paste0("preset-", pr, ".png"))
  tile(exc_restyle(as_excalidraw(plots$scatter, width = 600, height = 400), pr), f)
}

sheet <- function(pngs, file, cols, width) {
  imgs <- lapply(pngs, png::readPNG)
  rows <- ceiling(length(imgs) / cols)
  ratio <- dim(imgs[[1]])[1] / dim(imgs[[1]])[2]
  ragg::agg_png(file, width = width, height = round(width / cols * ratio * rows), res = 96,
                background = "white")
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(layout = grid::grid.layout(rows, cols)))
  for (i in seq_along(imgs)) {
    grid::pushViewport(grid::viewport(layout.pos.row = (i - 1) %/% cols + 1,
                                      layout.pos.col = (i - 1) %% cols + 1))
    grid::grid.raster(imgs[[i]], width = grid::unit(0.97, "npc"), height = grid::unit(0.97, "npc"))
    grid::popViewport()
  }
  grDevices::dev.off()
}
sheet(files, file.path(out, "gallery.png"), cols = 3, width = 1500)
sheet(file.path(tempdir(), paste0("preset-", presets, ".png")), file.path(out, "presets.png"),
      cols = 2, width = 1100)

party <- exc_scene(exc_text("Sticker party", 0, 0, font_size = 36)) |>
  exc_sticker("stick-figures:Girl", 0, 60, width = 90) |>
  exc_sticker("r-icons:1", 120, 70, width = 90) |>
  exc_sticker("bubbles:1", 230, 50, width = 160) |>
  exc_sticker("stars:3", 420, 70, width = 70, stroke = "#f08c00", fill = "#ffec99", fill_style = "solid") |>
  exc_peep(500, 40, size = 150, seed = "Ada", face = "smile") |>
  exc_peep(660, 40, size = 150, seed = "Grace", clothing = "#a5d8ff")
exc_save(party, file.path(out, "stickers.png"), scale = 1.2)

card <- exc_template_fill(
  exc_template_example(),
  data = list(metric = "Sketches drawn", value = "1,204", change = "+18% this month"),
  charts = list(trend = function(row) {
    set.seed(4)
    ggplot(data.frame(x = 1:12, y = cumsum(rnorm(12)) + 10), aes(x, y)) +
      geom_line(linewidth = 1, colour = "#1971c2") + labs(x = NULL, y = NULL) +
      theme_excalidraw(base_size = 11) +
      scale_x_continuous(breaks = c(1, 6, 12))
  })
)
exc_save(card, file.path(out, "template.png"), scale = 1.2)
message("done")
