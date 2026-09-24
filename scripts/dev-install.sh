#!/usr/bin/env bash
# Copy the working tree into Omarchy's plugin directory and have the shell
# rescan it. Omarchy won't load a symlinked plugin, so this copies. After
# changing QML, restart the shell as well (--restart).
set -euo pipefail

id=io.github.brandonpollack23.beautiful-workspace-bar
src=$(cd "$(dirname "$0")/.." && pwd)
dest=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$id

mkdir -p "$dest"
rsync -a --delete \
  --exclude .git --exclude docs --exclude tests --exclude scripts \
  --exclude prompt.md --exclude '*.swp' \
  "$src/" "$dest/"
omarchy-shell -q shell rescanPlugins || true
echo "Installed to $dest"

if [[ ${1:-} == --restart ]]; then
  # Restarting while the shell is still reloading the copied files has
  # crashed Quickshell, so give it a moment.
  sleep 3
  omarchy restart shell
fi
