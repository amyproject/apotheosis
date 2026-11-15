#!/bin/sh
# Copy the band39-live care app (github.com/suarezc/band39-live, care/web) into web/live/ unchanged, so
# product.html can show its Margaret and Lisa portals. Run after `git pull` in ../band39-live.
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"
src="$here/../band39-live/care/web"
rm -rf "$here/web/live"
rsync -aL --exclude replay.html --exclude '.DS_Store' "$src/" "$here/web/live/"
echo "web/live <- $src ($(find "$here/web/live" -type f | wc -l | tr -d ' ') files, unchanged)"
