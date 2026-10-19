"""Convert bundled fonts into formats R's FreeType-based devices can read.

- WOFF2 (Excalifont, Virgil) -> TTF. The WOFF2 originals stay for web use.
- Variable fonts (Caveat, Nunito, Cascadia Code) -> static Regular and Bold.

Usage: python3 data-raw/fonts.py inst/fonts
"""
import os
import sys

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

fonts_dir = sys.argv[1]


def woff2_to_ttf(name):
    src = os.path.join(fonts_dir, name + ".woff2")
    font = TTFont(src)
    font.flavor = None
    font.save(os.path.join(fonts_dir, name + ".ttf"))
    print("converted", name)


def set_style_names(font, family, style):
    """Give a static instance plain family/style names (ids 1, 2, 4, 6, 16, 17)."""
    full = f"{family} {style}"
    ps = f"{family.replace(' ', '')}-{style}"
    names = font["name"]
    for rec in list(names.names):
        if rec.nameID in (16, 17, 25):
            names.removeNames(nameID=rec.nameID)
    for pid, eid, lid in ((3, 1, 0x409), (1, 0, 0)):
        names.setName(family, 1, pid, eid, lid)
        names.setName(style, 2, pid, eid, lid)
        names.setName(full, 4, pid, eid, lid)
        names.setName(ps, 6, pid, eid, lid)
    if style == "Bold":
        font["OS/2"].fsSelection = (font["OS/2"].fsSelection & ~0b1000000) | 0b100000
        font["OS/2"].usWeightClass = 700
        font["head"].macStyle |= 1
    else:
        font["OS/2"].fsSelection = (font["OS/2"].fsSelection & ~0b100000) | 0b1000000
        font["OS/2"].usWeightClass = 400


def instantiate(vf_file, family, prefix):
    src = os.path.join(fonts_dir, vf_file)
    for style, weight in (("Regular", 400), ("Bold", 700)):
        vf = TTFont(src)
        inst = instancer.instantiateVariableFont(vf, {"wght": weight})
        set_style_names(inst, family, style)
        inst.save(os.path.join(fonts_dir, f"{prefix}-{style}.ttf"))
    os.remove(src)
    print("instanced", family)


woff2_to_ttf("Excalifont-Regular")
woff2_to_ttf("Virgil")
instantiate("Caveat-VF.ttf", "Caveat", "Caveat")
instantiate("Nunito-VF.ttf", "Nunito", "Nunito")
instantiate("CascadiaCode-VF.ttf", "Cascadia Code", "CascadiaCode")
