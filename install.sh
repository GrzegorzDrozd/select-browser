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

# 0. Check dependencies. zenity is required; the rest are recommended.
missing_required=()
command -v zenity &> /dev/null || missing_required+=("zenity")

if [ ${#missing_required[@]} -gt 0 ]; then
  echo "Error: missing required dependency: ${missing_required[*]}" >&2
  echo "select-browser cannot show its dialog without it." >&2
  echo "Install it first, for example:" >&2
  echo "  sudo apt install ${missing_required[*]}" >&2
  exit 1
fi

# Recommended tools (command -> apt package). Missing ones only degrade
# features, so warn instead of aborting.
declare -A recommended=(
  [xdg-open]="xdg-utils"      # 'Edit browser configs' button, set-as-default
  [xclip]="xclip"             # 'Copy to Clipboard' action
)
missing_recommended=()
for cmd in "${!recommended[@]}"; do
  command -v "$cmd" &> /dev/null || missing_recommended+=("${recommended[$cmd]}")
done
if [ ${#missing_recommended[@]} -gt 0 ]; then
  # Deduplicate package names.
  readarray -t pkgs < <(printf '%s\n' "${missing_recommended[@]}" | sort -u)
  echo "Warning: some optional features need packages that aren't installed:"
  echo "  ${pkgs[*]}"
  echo "  Install them for full functionality: sudo apt install ${pkgs[*]}"
  echo
fi

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
