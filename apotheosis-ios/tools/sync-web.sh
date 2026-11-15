#!/bin/sh
# Copy the ORIGINAL care app (band39-live/care/web, Charles's code) into web/ unchanged, then add the Apotheosis
# design layer next to it in web/apotheosis/ (new files only; no original file is edited). The iOS app injects
# web/apotheosis/apotheosis.css at load. Run after pulling band39-live.
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/../band39-live/care/web"
rm -rf "$here/web"
mkdir -p "$here/web"
rsync -aL --exclude replay.html --exclude '.DS_Store' "$src/" "$here/web/"
mkdir -p "$here/web/apotheosis"
cp "$here/theme/apotheosis.css" "$here/web/apotheosis/apotheosis.css"
# browser preview: the original index.html plus one <link> and the app class, saved as a separate file (index.html stays as is)
sed -e 's#</head>#<link rel="stylesheet" href="apotheosis/apotheosis.css" /><script>document.documentElement.classList.add("apo");document.documentElement.dataset.apoView=(new URLSearchParams(location.search).get("view")||"margaret");</script></head>#' \
  "$here/web/index.html" > "$here/web/apotheosis-preview.html"
echo "web/ <- $src (original, $(find "$here/web" -type f | wc -l | tr -d ' ') files) + apotheosis.css"
