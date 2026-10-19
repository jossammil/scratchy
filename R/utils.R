`%||%` <- function(x, y) if (is.null(x)) y else x

# Set a list entry to JSON `null` without dropping it from the list.
set_null <- function(x, name) {
  x[name] <- list(NULL)
  x
}

compact <- function(x) x[!vapply(x, is.null, logical(1))]

# Points given as x/y vectors, a two-column matrix/data frame, or a list of pairs.
as_xy <- function(x, y = NULL, arg = "x") {
  if (is.null(y)) {
    if (is.list(x) && !is.data.frame(x)) {
      m <- do.call(rbind, lapply(x, function(p) as.numeric(unlist(p))[1:2]))
    } else {
      m <- as.matrix(x)
    }
    if (ncol(m) < 2) cli::cli_abort("{.arg {arg}} needs two columns (x and y), or supply {.arg y}.")
    m <- m[, 1:2, drop = FALSE]
  } else {
    if (length(x) != length(y)) cli::cli_abort("{.arg x} and {.arg y} must have the same length.")
    m <- cbind(as.numeric(x), as.numeric(y))
  }
  storage.mode(m) <- "double"
  colnames(m) <- c("x", "y")
  m
}

# Matrix of points -> list of c(x, y) pairs (serialises as [[x, y], ...]).
xy_to_points <- function(m) {
  lapply(seq_len(nrow(m)), function(i) unname(m[i, ]))
}

points_to_xy <- function(points) {
  if (length(points) == 0) return(matrix(numeric(), ncol = 2, dimnames = list(NULL, c("x", "y"))))
  m <- matrix(as.numeric(unlist(points)), ncol = 2, byrow = TRUE)
  colnames(m) <- c("x", "y")
  m
}

pkg_file <- function(...) {
  path <- system.file(..., package = "excalidrawer")
  if (!nzchar(path)) cli::cli_abort("Can't find {.file {file.path(...)}} in the installed package.")
  path
}

deg2rad <- function(x) x * pi / 180
