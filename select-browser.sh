#!/bin/bash

# Directory this script lives in; per-browser configs live under browsers/.
# Each browser is a folder: browsers/<name>/command.txt (+ optional
# patterns.txt and an empty 'default' sentinel file).
#   command.txt  - launch command, e.g. "firefox" or "flatpak run org.mozilla.firefox".
#                  A literal %u token is replaced by the URL; otherwise the URL
#                  is appended as the last argument.
#   patterns.txt - URL substrings that auto-open with this browser (one per line,
#                  '#' comments and blank lines ignored).
#   default      - if this (empty) file exists, the browser is pre-selected.
# Resolve through any symlink (e.g. /usr/bin/select-browser or ~/.local/bin)
# so browsers/ is found next to the real script, not next to the symlink.
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
BROWSERS_DIR="$SCRIPT_DIR/browsers"

LINK=$*

# Print the cleaned, non-empty lines of a config file (strip '#' comments,
# trim surrounding whitespace). No-op if the file is missing.
read_config_lines() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"   # trim leading whitespace
    line="${line%"${line##*[![:space:]]}"}"   # trim trailing whitespace
    [[ -n "$line" ]] && printf '%s\n' "$line"
  done < "$file"
}

# Launch the browser configured in a given browser folder for a URL.
# Splits command.txt into words, substitutes %u with the URL (or appends it),
# and runs it. The URL is passed as a data argument, never interpolated into a
# shell string, so a malicious URL can't inject commands.
launch_browser() {
  local dir="$1" url="$2" cmdline
  cmdline="$(read_config_lines "$dir/command.txt" | head -n1)"
  [[ -z "$cmdline" ]] && return 1

  # Split the command using normal shell quoting, so a path with spaces works
  # when quoted, e.g.  "/opt/My Browser/run" --flag %u
  # command.txt is your own trusted config; the untrusted URL is never part of
  # this string, so quote-aware parsing here doesn't reopen the injection hole.
  # Globbing is disabled during the split so a stray '*' isn't expanded.
  local -a tokens args
  local reset_glob=0
  [[ $- == *f* ]] || reset_glob=1
  set -f
  eval "tokens=($cmdline)"
  [[ $reset_glob -eq 1 ]] && set +f
  local tok url_used=0
  for tok in "${tokens[@]}"; do
    if [[ "$tok" == "%u" ]]; then
      args+=("$url"); url_used=1
    else
      args+=("$tok")
    fi
  done
  [[ $url_used -eq 0 ]] && args+=("$url")

  "${args[@]}" &
}

# The label shown in the dialog: strip an optional leading number and one
# separator so a folder like "1-firefox" or "10 brave" sorts by the number but
# displays as "firefox" / "brave".
display_name() {
  local n="$1"
  if [[ "$n" =~ ^[0-9]+[-_.\ ]?(.+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$n"
  fi
}

# --- Discover browsers (folders containing command.txt) ---
# Sorted with -V (version sort) so numeric prefixes order naturally: a folder
# named "10-brave" comes after "2-chromium", not before it.
BROWSER_DIRS=()
if [[ -d "$BROWSERS_DIR" ]]; then
  while IFS= read -r dir; do
    [[ -f "$dir/command.txt" ]] && BROWSER_DIRS+=("$dir")
  done < <(find "$BROWSERS_DIR" -mindepth 1 -maxdepth 1 -type d | sort -V)
fi

# --- Automatic domain match: first browser with a matching pattern wins ---
for dir in "${BROWSER_DIRS[@]}"; do
  while IFS= read -r fragment; do
    if [[ "$LINK" == *"$fragment"* ]]; then
      launch_browser "$dir" "$LINK"
      exit 0
    fi
  done < <(read_config_lines "$dir/patterns.txt")
done

# --- Build the manual-selection dialog ---
# Browser rows first (one pre-selected), then the always-present defaults.
ZENITY_ARGS=()
for dir in "${BROWSER_DIRS[@]}"; do
  name="$(display_name "$(basename "$dir")")"
  if [[ -f "$dir/default" ]]; then
    ZENITY_ARGS+=("TRUE" "$name")
  else
    ZENITY_ARGS+=("FALSE" "$name")
  fi
done

# If no browser was marked default, pre-select the first one.
have_default=0
for ((i = 0; i < ${#ZENITY_ARGS[@]}; i += 2)); do
  [[ "${ZENITY_ARGS[i]}" == "TRUE" ]] && have_default=1 && break
done
if [[ $have_default -eq 0 && ${#ZENITY_ARGS[@]} -gt 0 ]]; then
  ZENITY_ARGS[0]="TRUE"
fi

# Always-available actions.
ZENITY_ARGS+=("FALSE" "Copy to Clipboard" "FALSE" "Edit browser configs…")

# Roughly size the window to the number of rows (plus header and buttons).
ROW_COUNT=$(( ${#ZENITY_ARGS[@]} / 2 ))
HEIGHT=$(( ROW_COUNT * 45 + 220 ))

BROWSER=$(zenity --list \
                 --radiolist \
                 --text "URL: ${LINK:0:100}..." \
                 --column='' \
                 --column='Action' \
                 --width=500 \
                 --height=$HEIGHT \
                 --title='Select Action for Link' \
                 "${ZENITY_ARGS[@]}")
EXIT_STATUS=$?

# Proceed only if the user clicked OK and selected something.
if [ $EXIT_STATUS -eq 0 ] && [ -n "$BROWSER" ]; then
  if [ "$BROWSER" == "Copy to Clipboard" ]; then
    if command -v xclip &> /dev/null; then
      echo -n "$LINK" | xclip -selection clipboard
      zenity --info --text="URL copied to clipboard!" --timeout=3
    else
      zenity --error --title="Dependency Missing" \
             --text="Error: 'xclip' is not installed. Please install it to use the copy feature.\n(e.g., sudo apt install xclip)"
    fi
  elif [ "$BROWSER" == "Edit browser configs…" ]; then
    # Copy the link to the clipboard first, so it isn't lost while editing.
    if command -v xclip &> /dev/null; then
      echo -n "$LINK" | xclip -selection clipboard
      zenity --info --text="URL copied to clipboard!" --timeout=1
    fi
    # Open the browsers/ folder so configs can be edited or new ones added.
    if command -v xdg-open &> /dev/null; then
      xdg-open "$BROWSERS_DIR" &
    else
      zenity --error --text="No file manager found. Edit configs here:\n$BROWSERS_DIR"
    fi
  else
    # A browser label: find the folder whose display name matches and launch it.
    # (The folder may carry a numeric prefix that the label doesn't.)
    for dir in "${BROWSER_DIRS[@]}"; do
      if [ "$(display_name "$(basename "$dir")")" == "$BROWSER" ]; then
        launch_browser "$dir" "$LINK"
        break
      fi
    done
  fi
fi

exit 0
