#!/bin/sh
# Builds tunnel.nes from src/main.s (needs cc65 and python3).
set -e
cd "$(dirname "$0")"
python3 tools_assets.py
ca65 -g -o main.o src/main.s
ld65 -C nes.cfg -o tunnel.nes main.o -Ln tunnel.lbl
rm -f main.o
echo "built $(pwd)/tunnel.nes ($(wc -c < tunnel.nes) bytes)"
