# Dev gallery: convert a range of plot types, save PNG/PDF/.excalidraw, and
# check every scene loads in the real Excalidraw.
#   Rscript dev/gallery.R
devtools::load_all(quiet = TRUE)
library(ggplot2)
source("dev/check-excalidraw.R")
out <- "dev/gallery"
dir.create(out, showWarnings = FALSE)

econ <- subset(economics, date > as.Date("2005-01-01"))
plots <- list(
  bars = ggplot(mpg, aes(class)) + geom_bar(fill = "#a5d8ff") +
    labs(title = "What do people drive?", x = NULL, y = "cars") +
    theme_excalidraw(grid = "y"),
  stacked = ggplot(mpg, aes(class, fill = drv)) + geom_bar() + scale_fill_excalidraw() +
    coord_flip() + labs(title = "Drive train by class", x = NULL),
  line = ggplot(econ, aes(date, unemploy / 1000)) + geom_line(linewidth = 1, colour = "#1971c2") +
    labs(title = "Unemployment (millions)", x = NULL, y = NULL),
  area = ggplot(econ, aes(date, psavert)) + geom_area(fill = "#b2f2bb", colour = "#2f9e44") +
    labs(title = "Personal savings rate", x = NULL, y = "%"),
  scatter = ggplot(mpg, aes(displ, hwy, colour = drv)) + geom_point(size = 2.5, alpha = 0.8) +
    scale_colour_excalidraw() + labs(title = "Bigger engines, fewer miles"),
  histogram = ggplot(faithful, aes(eruptions)) + geom_histogram(bins = 20, fill = "#ffec99") +
    labs(title = "Old Faithful eruptions"),
  boxplot = ggplot(mpg, aes(drv, hwy, fill = drv)) + geom_boxplot(show.legend = FALSE) +
    scale_fill_excalidraw() + labs(title = "Highway mpg by drive train"),
  facets = ggplot(penguins, aes(flipper_len, body_mass, colour = species)) + geom_point(size = 1.8) +
    facet_wrap(~island) + scale_colour_excalidraw() + labs(title = "Penguins"),
  pie = ggplot(data.frame(f = c("ink", "paper", "coffee"), n = c(3, 5, 2)), aes("", n, fill = f)) +
    geom_col(width = 1) + coord_polar("y") + scale_fill_excalidraw() + theme_void() +
    labs(title = "What sketching takes", fill = NULL)
)

results <- list()
for (nm in names(plots)) {
  theme <- if (nm %in% c("bars", "pie")) NULL else theme_excalidraw()
  s <- if (is.null(theme)) as_excalidraw(plots[[nm]], theme = NULL) else as_excalidraw(plots[[nm]])
  if (nm == "pie") s <- as_excalidraw(plots[[nm]] + theme_void(base_family = "Excalifont"), theme = NULL)
  write_excalidraw(s, file.path(out, paste0(nm, ".excalidraw")))
  exc_save(s, file.path(out, paste0(nm, ".png")), scale = 1.5)
  exc_save(s, file.path(out, paste0(nm, ".pdf")))
  chk <- excalidraw_check(s)
  results[[nm]] <- data.frame(plot = nm, elements = length(s$elements), excalidraw_ok = isTRUE(chk$ok),
                              restored = chk$n_restored %||% NA, errors = length(chk$errors))
}

# base graphics
s <- as_excalidraw(~ hist(faithful$waiting, col = "#ffd8a8", main = "Waiting time", xlab = "minutes"))
exc_save(s, file.path(out, "base-hist.png"), scale = 1.5)
results$base <- data.frame(plot = "base-hist", elements = length(s$elements),
                           excalidraw_ok = isTRUE(excalidraw_check(s)$ok), restored = NA, errors = NA)

# annotated
s <- as_excalidraw(plots$bars, theme = NULL) |>
  exc_mark(x = "suv", y = c(0, 62), type = "box") |>
  exc_note("SUVs win!", x = "midsize", y = 52, to = c("suv", 50)) |>
  exc_callout("only 5 of these", x = "2seater", y = 5, dx = 30, dy = -70) |>
  exc_mark(x = "compact", y = 47, type = "circle", padding = 10)
write_excalidraw(s, file.path(out, "annotated.excalidraw"))
exc_save(s, file.path(out, "annotated.png"), scale = 1.5)
results$annotated <- data.frame(plot = "annotated", elements = length(s$elements),
                                excalidraw_ok = isTRUE(excalidraw_check(s)$ok), restored = NA, errors = NA)

print(do.call(rbind, results), row.names = FALSE)
