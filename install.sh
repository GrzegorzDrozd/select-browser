#!/bin/bash
set -euo pipefail

# Installs select-browser: symlinks the script into a bin directory and
# registers a desktop entry so GNOME can offer it as the default web browser.
#
# By default it installs to ~/.local/bin (no root needed). To install
# system-wide instead:
#
#   BIN_DIR=/usr/bin ./install.sh
#
# A /usr/bin target uses sudo for the symlink.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/select-browser.sh"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
BIN_LINK="$BIN_DIR/select-browser"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/select-browser.desktop"

# 1. Make the script executable.
chmod +x "$SCRIPT"

# 2. Symlink it into the bin directory. Use sudo only when the directory
#    isn't writable by the current user (typically /usr/bin).
echo "Creating symlink: $BIN_LINK -> $SCRIPT"
mkdir -p "$BIN_DIR" 2>/dev/null || sudo mkdir -p "$BIN_DIR"
if [ -w "$BIN_DIR" ]; then
  ln -sf "$SCRIPT" "$BIN_LINK"
else
  sudo ln -sf "$SCRIPT" "$BIN_LINK"
fi

# 3. Write a desktop entry that handles http/https links. Exec points at the
#    absolute symlink path, so it works even if BIN_DIR isn't on PATH.
echo "Writing desktop entry: $DESKTOP_FILE"
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Select Browser
Comment=Pick a browser when opening a link
Exec=$BIN_LINK %u
Terminal=false
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;x-scheme-handler/https;
EOF

# 4. Refresh the desktop database so the entry shows up.
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true

# 5. Warn if the bin directory isn't on PATH (only matters for terminal use;
#    the desktop entry uses the absolute path above).
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Note: $BIN_DIR is not on your PATH. Add it to use 'select-browser' from a terminal." ;;
esac

echo
echo "Installed."
echo "Set it as default:  xdg-settings set default-web-browser select-browser.desktop"
echo "Or use GNOME Settings > Default Applications > Web."
