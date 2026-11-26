#!/bin/sh
# Archive distribuable du mod SEUL : un dossier passionphoto/ prêt à copier dans mods/.
# Contenu : mod.conf, init.lua, src/, textures/, sounds/, models/, locale/, licences, README, settingtypes.txt.
# Jamais : tools/, tests/ (dont le kit passionphoto_test), docs/, .claude/, .deps/, .run/, .headless/.
# Usage : tools/dist.sh <version>
set -eu
cd "$(dirname "$0")/.."
VERSION=${1:-dev}
OUT="dist/passionphoto-$VERSION.zip"
mkdir -p dist
[ -f "$OUT" ] && rm "$OUT"
STAGE=$(mktemp -d)
mkdir "$STAGE/passionphoto"
for f in mod.conf init.lua LICENSE LICENSE_MEDIA.txt README.md settingtypes.txt; do
	[ -f "$f" ] && cp "$f" "$STAGE/passionphoto/"
done
for d in src textures sounds models locale; do
	[ -d "$d" ] && cp -R "$d" "$STAGE/passionphoto/"
done
find "$STAGE/passionphoto" \( -name '.DS_Store' -o -name '*.old' -o -name '*.px' \) -delete
(cd "$STAGE" && zip -qr - passionphoto) > "$OUT"
rm -r "$STAGE"
echo "$OUT"
