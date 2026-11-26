# A small XML reader for the SVG that svglite writes, used when converting
# plots. It replaces xml2 here because xml2's WebAssembly build crashes webR
# (memory access out of bounds) when it reads namespaced documents like these
# twice, which broke as_excalidraw() in denr. svglite's output is regular:
# elements, attributes in quotes, character data in <style>, text in <text>.
#
# A node is a list: name, attrs (named character vector), children (list of
# nodes), text (character data directly inside it).

svg_parse <- function(text) {
  text <- paste(text, collapse = "\n")
  tokens <- regmatches(text, gregexpr(
    "<!--[\\s\\S]*?-->|<!\\[CDATA\\[[\\s\\S]*?\\]\\]>|<\\?[\\s\\S]*?\\?>|<![^>]*>|<[^>]+>|[^<]+",
    text, perl = TRUE))[[1]]
  root <- list(name = "#document", attrs = character(), children = list(), text = "")
  stack <- list(root)
  for (tok in tokens) {
    first <- substr(tok, 1L, 2L)
    if (first == "<!" || first == "<?") {
      if (startsWith(tok, "<![CDATA[")) {
        n <- length(stack)
        stack[[n]]$text <- paste0(stack[[n]]$text, substr(tok, 10L, nchar(tok) - 3L))
      }
      next
    }
    if (first == "</") {
      n <- length(stack)
      if (n < 2L) next
      done <- stack[[n]]
      stack[[n]] <- NULL
      stack[[n - 1L]]$children[[length(stack[[n - 1L]]$children) + 1L]] <- done
      next
    }
    if (substr(tok, 1L, 1L) == "<") {
      self_closing <- endsWith(tok, "/>")
      inner <- substr(tok, 2L, nchar(tok) - if (self_closing) 2L else 1L)
      name <- regmatches(inner, regexpr("^[^\\s/>]+", inner, perl = TRUE))
      node <- list(name = name, attrs = svg_attrs(substr(inner, nchar(name) + 1L, nchar(inner))),
                   children = list(), text = "")
      if (self_closing) {
        n <- length(stack)
        stack[[n]]$children[[length(stack[[n]]$children) + 1L]] <- node
      } else {
        stack[[length(stack) + 1L]] <- node
      }
      next
    }
    # Character data: kept where it matters (text elements); layout whitespace is dropped.
    if (grepl("\\S", tok, perl = TRUE)) {
      n <- length(stack)
      stack[[n]]$text <- paste0(stack[[n]]$text, svg_unescape(tok))
    }
  }
  # Close anything left open (not expected from svglite).
  while (length(stack) > 1L) {
    n <- length(stack)
    done <- stack[[n]]
    stack[[n]] <- NULL
    stack[[n - 1L]]$children[[length(stack[[n - 1L]]$children) + 1L]] <- done
  }
  doc <- stack[[1L]]
  svg <- Filter(function(ch) ch$name == "svg", doc$children)
  if (!length(svg)) cli::cli_abort("The plot could not be read: the captured SVG has no {.code <svg>} element.")
  svg[[1L]]
}

svg_attrs <- function(s) {
  m <- regmatches(s, gregexpr("([^\\s=]+)\\s*=\\s*(\"[^\"]*\"|'[^']*')", s, perl = TRUE))[[1]]
  if (!length(m)) return(character())
  keys <- sub("\\s*=[\\s\\S]*$", "", m, perl = TRUE)
  values <- sub("^[^=]*=\\s*", "", m, perl = TRUE)
  values <- svg_unescape(substr(values, 2L, nchar(values) - 1L))
  stats::setNames(values, keys)
}

svg_unescape <- function(x) {
  if (!any(grepl("&", x, fixed = TRUE))) return(x)
  x <- gsub("&lt;", "<", x, fixed = TRUE)
  x <- gsub("&gt;", ">", x, fixed = TRUE)
  x <- gsub("&quot;", "\"", x, fixed = TRUE)
  x <- gsub("&apos;", "'", x, fixed = TRUE)
  x <- gsub("&#39;", "'", x, fixed = TRUE)
  num <- function(x, pattern, base) {
    m <- gregexpr(pattern, x, perl = TRUE)
    regmatches(x, m) <- lapply(regmatches(x, m), function(codes) {
      vapply(codes, function(code) intToUtf8(strtoi(gsub("[&#x;]", "", code), base)), "")
    })
    x
  }
  x <- num(x, "&#[0-9]+;", 10L)
  x <- num(x, "&#x[0-9A-Fa-f]+;", 16L)
  gsub("&amp;", "&", x, fixed = TRUE)
}

# The few lookups the plot converter needs.
sx_attr <- function(node, name) {
  v <- node$attrs[name]
  if (is.null(v) || is.na(v)) NA_character_ else unname(v)
}
sx_children <- function(node) node$children
sx_name <- function(node) node$name
sx_text <- function(node) {
  paste0(node$text, paste(vapply(node$children, sx_text, ""), collapse = ""))
}
sx_child <- function(node, name) {
  for (ch in node$children) if (ch$name == name) return(ch)
  NULL
}
sx_find_all <- function(node, name) {
  out <- list()
  for (ch in node$children) {
    if (ch$name == name) out[[length(out) + 1L]] <- ch
    out <- c(out, sx_find_all(ch, name))
  }
  out
}
