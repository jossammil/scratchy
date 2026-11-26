# Writes srcjs/src/extras/presets.json: the style presets and font table the
# browser extras use, taken from the R package so both stay the same.
#   Rscript data-raw/extras-json.R
devtools::load_all(quiet = TRUE)
presets <- lapply(.presets, function(p) {
  f <- resolve_font(p$font)
  list(roughness = p$roughness, font = f$name, fontFamily = f$id, customFont = f$custom,
       ink = p$ink, background = p$background,
       fillStyle = normalize_style(list(fillStyle = p$fill_style))$fillStyle,
       strokeWidth = normalize_style(list(strokeWidth = p$stroke_width))$strokeWidth,
       bowing = p$bowing)
})
fonts <- lapply(seq_len(nrow(.fonts)), function(i) {
  list(name = .fonts$name[i], fontFamily = if (is.na(.fonts$id[i])) 5L else .fonts$id[i],
       editor = !is.na(.fonts$id[i]))
})
jsonlite::write_json(list(presets = presets, fonts = fonts), "srcjs/src/extras/presets.json",
                     auto_unbox = TRUE, pretty = TRUE, null = "null")
