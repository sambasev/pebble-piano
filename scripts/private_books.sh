#!/bin/sh
# Builds the private LilyPond test set: two-hand beginner pieces engraved in LilyPond, compiled
# to page images and MIDI (the answer key) in .build/private-books/out.
#
# PRIVATE: these books have no licence ("© Heart & Trust Music Engraving … educational copying
# welcome"). Use them to test the reader only: never commit, ship or show them in the demo.
# .build/ is git-ignored.
#
#   sh scripts/private_books.sh
#   python3 -m pip install numpy scipy pillow mido
#   python3 scripts/eval_lilypond.py .build/private-books/out
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
dir="$root/.build/private-books"
mkdir -p "$dir/out"
cd "$dir"

[ -d fte ] || git clone --depth 1 https://github.com/nathanaelmeister/Piano_-_First_two_hand_exercises fte
[ -d czerny ] || git clone --depth 1 https://github.com/nathanaelmeister/The-LilyPond-Easy-Czerny-Variations-Piano-Book czerny

# LilyPond: Homebrew's if installed, else the PyPI build in a venv here.
if command -v lilypond >/dev/null 2>&1; then
    ly=lilypond
else
    [ -x venv/bin/lilypond ] || { python3 -m venv venv && venv/bin/pip install -q lilypond; }
    ly="$dir/venv/bin/lilypond"
fi
"$ly" --version | head -1

# One page image (220 dpi, like the book importer) and one MIDI file per piece.
cd fte/single-pages
for f in *.ly; do
    name=${f%.ly}
    [ -f "$dir/out/$name.midi" ] && continue
    "$ly" -s --png -dresolution=220 -o "$dir/out/$name" "$f" || echo "failed: $name"
done

# The Czerny book was written for LilyPond 2.18: patch what newer versions reject. (Its pieces
# have no \midi blocks: it is used as page images only, for now.)
cd "$dir/czerny"
sed -i.orig 's/\\on-the-fly #print-page-number-check-first//' global-files/paper.ily
for f in global-files/*.ily; do sed -i.orig 's/(_ "/(G_ "/g' "$f"; done
mkdir -p "$dir/out/czerny"
"$ly" -s --png -dresolution=220 -o "$dir/out/czerny/book" Czerny-Variations-Easy_-_Book_1.ly || echo "failed: czerny"
echo "done: $(ls "$dir/out"/*.midi | wc -l) pieces in $dir/out"
