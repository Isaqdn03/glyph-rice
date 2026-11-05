# Nautilus: right-click → Send via LocalSend. Needs nautilus-python.
# After Omarchy's default/nautilus-python/extensions/localsend.py (MIT).
import shutil

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import GObject, Gio, Nautilus


class LocalSend(GObject.GObject, Nautilus.MenuProvider):
    def get_file_items(self, *args):
        files = args[-1]  # Nautilus 4: (files); 3: (window, files)
        exe = shutil.which("localsend")
        paths = []
        for f in files:
            p = f.get_location().get_path() if f.get_location() else None
            if p and p not in paths:
                paths.append(p)
        if not exe or not paths:
            return []
        item = Nautilus.MenuItem(name="LocalSend::send", label="Send via LocalSend", icon="localsend")
        item.connect("activate", lambda *_: Gio.Subprocess.new([exe, *paths], Gio.SubprocessFlags.NONE))
        return [item]
