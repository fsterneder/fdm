#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 || ! "$1" =~ ^https:// ]]; then
  echo "Usage: bash scripts/make-cask.sh https://HOST/path/Metronom-0.1.0.zip" >&2
  exit 1
fi
archive="dist/Metronom-0.1.0.zip"
[[ -f "$archive" ]] || { echo "Run scripts/build.sh first." >&2; exit 1; }
# Reject characters that could alter the generated Ruby formula.
case "$1" in *\"*|*\\*|*\#*|*$'\n'*|*$'\r'*) echo "Unsupported URL characters" >&2; exit 1;; esac
checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"
mkdir -p dist/Casks
cat > dist/Casks/metronom.rb <<CASK
cask "metronom" do
  version "0.1.0"
  sha256 "$checksum"
  url "$1"
  name "Metronom"
  desc "Compact desktop metronome with tap tempo and beat accents"
  homepage "${1%/*}"
  depends_on macos: ">= :ventura"
  app "Metronom.app"
end
CASK
echo "Created dist/Casks/metronom.rb for the archive built on this Mac."
