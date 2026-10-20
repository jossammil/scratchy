# Chart building for Sketch Studio: turn the app's choices into ggplot code
# (shown to the user, so the chart can be recreated in R) and evaluate it.

.studio_charts <- c(
  "Bars (count)" = "bar", "Columns (values)" = "col", "Lines" = "line", "Area" = "area",
  "Scatter" = "point", "Histogram" = "histogram", "Boxplot" = "boxplot", "Pie" = "pie"
)

studio_needs <- function(type) {
  switch(type,
    bar = c("x"), histogram = c("x"),
    col = c("x", "y"), line = c("x", "y"), area = c("x", "y"), point = c("x", "y"),
    boxplot = c("x", "y"), pie = c("x", "y")
  )
}

col_sym <- function(col) if (make.names(col) == col) col else paste0("`", col, "`")

# Build the ggplot code for a chart spec (a list of the app's choices).
studio_code <- function(spec, data_name = "data") {
  has <- function(v) !is.null(v) && nzchar(v) && v != "(none)"
  aes_args <- c()
  if (spec$type == "pie") {
    aes_args <- c(x = '""', y = col_sym(spec$y), fill = col_sym(spec$x))
  } else {
    aes_args <- c(x = col_sym(spec$x))
    if ("y" %in% studio_needs(spec$type)) aes_args <- c(aes_args, y = col_sym(spec$y))
    if (has(spec$group)) {
      aes_args <- c(aes_args, stats::setNames(col_sym(spec$group),
                                              if (spec$type %in% c("line", "point")) "colour" else "fill"))
    }
  }
  aes_txt <- paste0(names(aes_args), " = ", aes_args, collapse = ", ")
  fill <- spec$fill %||% "#a5d8ff"
  ink <- spec$ink %||% "#1971c2"
  grouped <- has(spec$group) || spec$type == "pie"
  geom <- switch(spec$type,
    bar = if (grouped) "geom_bar()" else sprintf('geom_bar(fill = "%s")', fill),
    col = if (grouped) "geom_col()" else sprintf('geom_col(fill = "%s")', fill),
    line = if (grouped) "geom_line(linewidth = 1)" else sprintf('geom_line(linewidth = 1, colour = "%s")', ink),
    area = if (grouped) "geom_area()" else sprintf('geom_area(fill = "%s", colour = "%s")', fill, ink),
    point = if (grouped) "geom_point(size = 2.5)" else sprintf('geom_point(size = 2.5, colour = "%s")', ink),
    histogram = if (grouped) "geom_histogram(bins = 20)" else sprintf('geom_histogram(bins = 20, fill = "%s")', fill),
    boxplot = if (grouped) "geom_boxplot()" else sprintf('geom_boxplot(fill = "%s")', fill),
    pie = "geom_col(width = 1)"
  )
  lines <- c(sprintf("ggplot(%s, aes(%s))", data_name, aes_txt), geom)
  if (grouped) {
    lines <- c(lines, if (spec$type %in% c("line", "point")) "scale_colour_excalidraw()" else "scale_fill_excalidraw()")
  }
  if (has(spec$facet)) lines <- c(lines, sprintf("facet_wrap(vars(%s))", col_sym(spec$facet)))
  if (spec$type == "pie") lines <- c(lines, 'coord_polar("y")')
  labs <- c(title = spec$title, subtitle = spec$subtitle)
  labs <- labs[!is.na(labs) & nzchar(labs)]
  if (length(labs)) {
    lines <- c(lines, sprintf("labs(%s)", paste0(names(labs), " = ", vapply(labs, deparse, ""), collapse = ", ")))
  }
  theme <- if (spec$type == "pie") {
    sprintf('theme_void(base_family = "%s", base_size = 15)', resolve_font(spec$font %||% "Excalifont")$family)
  } else {
    sprintf('theme_excalidraw(grid = "%s", base_family = "%s")', spec$grid %||% "y",
            resolve_font(spec$font %||% "Excalifont")$family)
  }
  paste(c(lines, theme), collapse = " +\n  ")
}

studio_plot <- function(code, data) {
  env <- new.env(parent = asNamespace("excalidrawer"))
  env$data <- data
  for (f in getNamespaceExports("ggplot2")) {
    if (!exists(f, env, inherits = FALSE)) assign(f, getExportedValue("ggplot2", f), env)
  }
  eval(parse(text = code), env)
}

studio_datasets <- function() {
  list(
    "Cars (mpg)" = function() as.data.frame(ggplot2::mpg),
    "Penguins" = function() as.data.frame(stats::na.omit(get("penguins", envir = asNamespace("datasets")))),
    "Economics" = function() as.data.frame(ggplot2::economics),
    "Old Faithful" = function() datasets::faithful,
    "Iris" = function() datasets::iris,
    "Motor cars (mtcars)" = function() cbind(car = rownames(datasets::mtcars), datasets::mtcars)
  )
}

# Default axes: a categorical column with a handful of levels (3-9, the
# more the better) for x, and the first numeric column for y.
studio_defaults <- function(data) {
  cols <- names(data)
  cat <- cols[vapply(data, function(v) is.character(v) || is.factor(v), logical(1))]
  num <- cols[vapply(data, is.numeric, logical(1))]
  levels <- vapply(cat, function(cl) length(unique(data[[cl]])), 1)
  ok <- cat[levels >= 3 & levels <= 9]
  x <- if (length(ok)) ok[which.max(levels[ok])] else if (length(cat)) cat[1] else cols[1]
  list(x = x, y = if (length(num)) num[1] else cols[min(2, length(cols))])
}

studio_read_text <- function(txt) {
  sep <- if (grepl("\t", txt)) "\t" else if (grepl(";", txt) && !grepl(",", txt)) ";" else ","
  utils::read.csv(text = txt, sep = sep, stringsAsFactors = FALSE, check.names = FALSE)
}
