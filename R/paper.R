.papers <- list(
  plain = list(),
  graph = list(grid = 20, major = 5, minor_col = "#e7f5ff", major_col = "#a5d8ff"),
  dots = list(dots = 20, dot_col = "#adb5bd"),
  lines = list(rule = 32, rule_col = "#a5d8ff", margin = 64, margin_col = "#ffa8a8"),
  kraft = list(background = "#dcc7a1", speckle_col = "#c8ad7f"),
  blueprint = list(background = "#1d4f86", grid = 20, major = 5,
                   minor_col = "#2b62a0", major_col = "#4a7fbf"),
  chalkboard = list(background = "#2f3d33", speckle_col = "#3a4a3e")
)

#' Paper backgrounds
#'
#' Names of the paper backgrounds the native renderer can draw behind a
#' scene. Pass one as `paper =` to [exc_save()], [exc_grob()] or `plot()`.
#'
#' @return A character vector.
#' @export
#' @examples
#' exc_papers()
exc_papers <- function() names(.papers)

paper_spec <- function(paper) {
  if (is.null(paper) || identical(paper, "plain")) return(NULL)
  spec <- .papers[[paper]]
  if (is.null(spec)) cli::cli_abort("Unknown paper {.val {paper}}. Use one of {.val {exc_papers()}}.")
  c(list(name = paper), spec)
}

paper_grobs <- function(p, cv, s) {
  if (is.null(p)) return(list())
  x0 <- cv[["x0"]]; y0 <- cv[["y0"]]; x1 <- x0 + cv[["w"]]; y1 <- y0 + cv[["h"]]
  out <- list()
  native <- function(v) grid::unit(v, "native")
  if (!is.null(p$grid)) {
    xs <- seq(ceiling(x0 / p$grid) * p$grid, x1, by = p$grid)
    ys <- seq(ceiling(y0 / p$grid) * p$grid, y1, by = p$grid)
    major_x <- (round(xs / p$grid) %% p$major) == 0
    major_y <- (round(ys / p$grid) %% p$major) == 0
    for (major in c(FALSE, TRUE)) {
      vx <- xs[major_x == major]; vy <- ys[major_y == major]
      out <- c(out, list(
        grid::segmentsGrob(native(vx), native(rep(-y0, length(vx))), native(vx), native(rep(-y1, length(vx))),
                           gp = grid::gpar(col = if (major) p$major_col else p$minor_col, lwd = s * 96)),
        grid::segmentsGrob(native(rep(x0, length(vy))), native(-vy), native(rep(x1, length(vy))), native(-vy),
                           gp = grid::gpar(col = if (major) p$major_col else p$minor_col, lwd = s * 96))
      ))
    }
  }
  if (!is.null(p$dots)) {
    xs <- seq(ceiling(x0 / p$dots) * p$dots, x1, by = p$dots)
    ys <- seq(ceiling(y0 / p$dots) * p$dots, y1, by = p$dots)
    g <- expand.grid(x = xs, y = ys)
    out <- c(out, list(grid::circleGrob(native(g$x), native(-g$y), r = grid::unit(1.2 * s, "inches"),
                                        gp = grid::gpar(fill = p$dot_col, col = NA))))
  }
  if (!is.null(p$rule)) {
    ys <- seq(y0 + p$rule, y1, by = p$rule)
    out <- c(out, list(
      grid::segmentsGrob(native(rep(x0, length(ys))), native(-ys), native(rep(x1, length(ys))), native(-ys),
                         gp = grid::gpar(col = p$rule_col, lwd = s * 96)),
      grid::segmentsGrob(native(x0 + p$margin), native(-y0), native(x0 + p$margin), native(-y1),
                         gp = grid::gpar(col = p$margin_col, lwd = 1.5 * s * 96))
    ))
  }
  if (!is.null(p$speckle_col)) {
    n <- round(cv[["w"]] * cv[["h"]] / 900)
    old <- if (exists(".Random.seed", globalenv())) get(".Random.seed", globalenv()) else NULL
    set.seed(7)
    sx <- stats::runif(n, x0, x1); sy <- stats::runif(n, y0, y1); sr <- stats::runif(n, 0.4, 1.4)
    if (!is.null(old)) assign(".Random.seed", old, globalenv())
    out <- c(out, list(grid::circleGrob(native(sx), native(-sy), r = grid::unit(sr * s, "inches"),
                                        gp = grid::gpar(fill = p$speckle_col, col = NA))))
  }
  out
}
