# select-browser

A link handler that asks which browser to open a URL in, and can route certain
URLs to a specific browser automatically. Click a link anywhere, get a small
dialog, pick a browser. Work URLs can skip the dialog and open in the browser
you assigned them.

Everything is configured with plain text files under `browsers/`. Adding a
browser or a routing rule means editing a file, not the script.

## How it works

When a link is opened, the script checks each browser's `patterns.txt` for a
substring that appears in the URL. The first match wins, and that browser opens
the link with no dialog. If nothing matches, a zenity dialog lists every
configured browser plus "Copy to Clipboard" and "Edit browser configs...".

## Requirements

- `bash`
- `zenity` for the dialog
- `xdg-utils` for `xdg-open` (the config editor button) and `xdg-settings`
- `xclip` (optional, only needed for the Copy to Clipboard action)
- The browsers you want to use, installed and on your `PATH`

On Debian or Ubuntu:

```
sudo apt install zenity xdg-utils xclip
```

## Install

Clone the repo, then run the installer:

```
git clone https://github.com/<you>/select-browser.git
cd select-browser
./install.sh
```

The installer does three things:

- makes `select-browser.sh` executable
- symlinks it to `~/.local/bin/select-browser`
- writes a desktop entry to `~/.local/share/applications/select-browser.desktop`
  so GNOME can treat it as a browser

Installing to `~/.local/bin` is the safer default: no `sudo`, nothing touches
system directories, and it stays scoped to your user. The one requirement is
that `~/.local/bin` is on your `PATH`, which it is on most current setups. The
desktop entry uses the absolute path either way, so links still work even if it
is not.

To install system-wide instead (uses `sudo` for the symlink):

```
BIN_DIR=/usr/bin ./install.sh
```

The repo has to stay where you cloned it. The symlink points back to
`select-browser.sh`, and the script reads its `browsers/` config from that same
folder.

## Set it as the default browser in GNOME

After installing, register it as the handler for web links. From a terminal:

```
xdg-settings set default-web-browser select-browser.desktop
```

Or do it through the GUI. Open Settings, go to Default Applications, and choose
"Select Browser" under Web.

To confirm it took:

```
xdg-settings get default-web-browser
```

That should print `select-browser.desktop`. From now on, links opened from
other apps run through the picker.

## Configuring browsers

Each browser is a folder under `browsers/`:

```
browsers/
  firefox/
    command.txt
    patterns.txt
    default
  chromium/
    command.txt
    patterns.txt
```

### command.txt

The command that launches the browser, for example `firefox` or
`flatpak run org.mozilla.firefox`. A literal `%u` token is replaced with the
URL. If there is no `%u`, the URL is appended as the last argument, so a plain
`firefox` works fine.

The URL is always passed as a separate argument, never pasted into a shell
string, so a hostile link cannot inject commands.

### patterns.txt

URL substrings that auto-open in this browser, one per line. Blank lines and
lines starting with `#` are ignored. Matching is a plain substring test against
the full URL, so `github.com/<org_name>` matches any path under that repo owner.

Leave the file empty (or drop it) if a browser should only ever be picked
manually.

### default

An empty marker file. If it exists, that browser is pre-selected in the dialog.
Mark only one browser this way. If none are marked, the first one is selected.

### Adding a browser

Create a folder, add a `command.txt`, and you are done:

```
mkdir -p browsers/brave
echo 'flatpak run com.brave.Browser' > browsers/brave/command.txt
```

The "Edit browser configs..." entry in the dialog opens the `browsers/` folder
in your file manager, which is the quick way to tweak all of this later.

## Uninstall

If it is your default browser, point that setting at a real browser first.
Skip this step and GNOME keeps a default that no longer exists, so links may
stop opening.

```
xdg-settings set default-web-browser firefox.desktop
```

Then remove the symlink and desktop entry:

```
rm ~/.local/bin/select-browser
rm ~/.local/share/applications/select-browser.desktop
```

If you installed to `/usr/bin`, remove that symlink with `sudo` instead:

```
sudo rm /usr/bin/select-browser
```
