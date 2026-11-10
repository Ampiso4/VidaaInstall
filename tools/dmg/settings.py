# Mise en page du .dmg pour dmgbuild (écrit le .DS_Store sans piloter le Finder).
import os
import unicodedata

# Le disque HFS+ stocke les noms en NFD : les clés du .DS_Store doivent suivre.
def nfd(p):
    return unicodedata.normalize('NFD', os.path.basename(p))
app = defines['app']
guide = defines['guide']
files = [app, guide]
symlinks = {'Applications': '/Applications'}
icon = defines['volicon']
background = defines['background']
format = 'UDZO'
filesystem = 'HFS+'
window_rect = ((200, 140), (640, 428))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = 'auto'
arrange_by = None
icon_size = 84
text_size = 12
label_pos = 'bottom'
icon_locations = {
    nfd(app): (170, 175),
    'Applications': (470, 175),
    nfd(guide): (480, 312),
}
hide_extensions = [nfd(app), nfd(guide)]
