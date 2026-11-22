#!/bin/sh
# Plays a round with the bot and writes nes/gifs/round_<n>.gif. Usage: record_gif.sh [seed]
set -e
cd "$(dirname "$0")"
seed=${1:-1}
tmp=$(mktemp -d)
node tools/record_round.mjs "$tmp" "$seed"
python3 tools/make_gif.py "$tmp" "gifs/round_${seed}.gif"
rm -rf "$tmp"
