# excalidrawer

Excalidraw-style charts, drawings and slides from R.

excalidrawer turns ggplot2 (and base R) plots into **editable
[Excalidraw](https://excalidraw.com) drawings**. It also draws Excalidraw
scenes **offline in R**, with the same rough.js engine, seeds and handwriting
fonts that Excalidraw uses. You get hand-drawn PNG/SVG/PDF images for reports,
plus `.excalidraw` files you can open and tweak by hand.

> Not affiliated with or endorsed by Excalidraw.

## Install

```r
# from a local checkout
devtools::install("path/to/excalidrawer")
```

## Quick start

```r
library(excalidrawer)
library(ggplot2)

p <- ggplot(mpg, aes(class)) + geom_bar(fill = "#a5d8ff") +
  labs(title = "What do people drive?", x = NULL, y = "cars")

# Draw it hand-drawn style (RStudio, knitr/Quarto, or ggsave)
sketch(p)
ggsave("cars.png", sketch(p), width = 8, height = 5)

# Or make an editable Excalidraw scene, annotate it with data values, and save
s <- as_excalidraw(p) |>
  exc_mark(x = "suv", y = c(0, 62), type = "box") |>
  exc_note("SUVs win!", x = "midsize", y = 52, to = c("suv", 50)) |>
  exc_callout("only 5 of these", x = "2seater", y = 5)

write_excalidraw(s, "cars.excalidraw")   # open at excalidraw.com
exc_save(s, "cars.png", scale = 2)        # or .svg / .pdf
```

Build drawings from scratch:

```r
exc_scene(
  exc_rect(0, 0, 160, 80, label = "Idea", fill = "yellow", fill_style = "solid", rounded = TRUE),
  exc_arrow(c(170, 300), c(40, 40), label = "becomes"),
  exc_ellipse(310, 0, 160, 90, label = "Chart", fill = "blue", fill_style = "hachure")
) |>
  exc_save("idea.png")
```

Change the whole look with a preset: `whiteboard`, `xkcd`, `blueprint`,
`chalkboard`, `pencil` or `marker`.

```r
sketch(p, preset = "chalkboard")
exc_restyle(s, "blueprint") |> exc_save("blueprint.png")
```

## What's inside

| Area | Functions |
|---|---|
| Scenes and elements | `exc_scene()`, `exc_rect()`, `exc_ellipse()`, `exc_diamond()`, `exc_text()`, `exc_line()`, `exc_arrow()`, `exc_freedraw()`, `exc_image()`, `exc_frame()`, `exc_group()`, `exc_modify()` |
| Files | `read_excalidraw()`, `write_excalidraw()`, `read_excalidraw_lib()`, `write_excalidraw_lib()`, `exc_library_item()` |
| Rendering | `exc_save()` (PNG, JPEG, SVG with embedded fonts, PDF), `exc_grob()`, `plot()` |
| ggplot2 | `as_excalidraw()`, `sketch()`, `theme_excalidraw()`, `scale_fill_excalidraw()`, `scale_colour_excalidraw()` |
| Annotations | `exc_note()`, `exc_callout()`, `exc_mark()`, `exc_title()`, `exc_data_to_px()` |
| Style | `exc_style()`, `exc_set_style()`, `exc_preset()`, `exc_restyle()`, `exc_papers()`, `exc_fonts()`, `excalidraw_colors()` |

## Credits

The bundled third-party pieces keep their own licences (see `inst/COPYRIGHTS`
and `inst/fonts/LICENSES/`):

- rough.js (MIT, Preet Shihn)
- perfect-freehand (MIT, Steve Ruiz)
- lz-string (MIT)
- Excalidraw's shape and font-metric logic, ported to JavaScript for V8 (MIT)
- Excalifont and Virgil (OFL-1.1)
- Comic Shanns (MIT)
- Caveat, Patrick Hand, Architects Daughter, Gochi Hand, Nunito, Lilita One and Cascadia Code (OFL-1.1)
