.id_chars <- c(LETTERS, letters, as.character(0:9), "_", "-")
.base62 <- c(as.character(0:9), LETTERS, letters)

# Random element id in the style of Excalidraw's nanoid ids. Uses R's RNG, so
# set.seed() makes scenes reproducible.
new_id <- function(n = 1) {
  vapply(seq_len(n), function(i) paste(sample(.id_chars, 20, replace = TRUE), collapse = ""), "")
}

new_seed <- function(n = 1) sample.int(2147483646L, n, replace = TRUE)

timestamp_ms <- function() {
  getOption("excalidrawer.timestamp", round(as.numeric(Sys.time()) * 1000))
}

# Ordered fractional-index keys ("a0", "a1", ..., "az", "b00", ...), compatible
# with Excalidraw's fractional indexing.
index_keys <- function(n) {
  if (n == 0) return(character())
  out <- character(n)
  i <- 0L
  len <- 1L
  head <- 1L
  while (i < n) {
    cap <- 62^len
    take <- min(n - i, cap)
    k <- seq_len(take) - 1
    digits <- vapply(k, function(v) {
      d <- character(len)
      for (p in len:1) {
        d[p] <- .base62[v %% 62 + 1]
        v <- v %/% 62
      }
      paste(d, collapse = "")
    }, "")
    out[i + seq_len(take)] <- paste0(letters[head], digits)
    i <- i + take
    len <- len + 1L
    head <- head + 1L
  }
  out
}

# Keys must be unique and strictly increasing in C-locale (byte) order.
keys_in_order <- function(keys) {
  if (any(vapply(keys, is.null, logical(1)))) return(FALSE)
  keys <- unlist(keys)
  !anyDuplicated(keys) && identical(order(keys, method = "radix"), seq_along(keys))
}
