#!/bin/bash
# Rebuilds generated files and the download zips served by the website (docs/downloads).
set -e
cd "$(dirname "$0")"
python3 shared/build-chrome-policy.py
for f in hosts-block.txt youtube-domains.txt ubol-filters.txt; do
  cp shared/$f mac/src/$f; cp shared/$f windows/src/$f
done
chmod +x mac/install.sh mac/src/*.sh mac/src/lockboxctl
mkdir -p docs/downloads build
rm -rf build/* docs/downloads/*.zip
cp -r mac build/lockbox-mac && cp -r windows build/lockbox-windows
(cd build && zip -qr ../docs/downloads/lockbox-mac.zip lockbox-mac && zip -qr ../docs/downloads/lockbox-windows.zip lockbox-windows)
rm -rf build
ls -la docs/downloads
