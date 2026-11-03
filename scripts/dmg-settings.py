# dmgbuild settings for the disk image window. Positions match scripts/make-dmg-background.swift.
# Used by scripts/package.sh: dmgbuild -s scripts/dmg-settings.py -D app=dist/Ports.app Ports Ports.dmg
format = "UDZO"
files = [defines["app"]]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"
background = "Resources/dmg-background.tiff"
window_rect = ((200, 160), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {"Ports.app": (190, 200), "Applications": (470, 200)}
