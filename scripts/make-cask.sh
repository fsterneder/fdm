#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 || ! "$1" =~ ^https:// ]]; then
  echo "Usage: bash scripts/make-cask.sh https://HOST/path/fdm-0.16.8.zip" >&2
  exit 1
fi
archive="dist/fdm-0.16.8.zip"
[[ -f "$archive" ]] || { echo "Run scripts/build.sh first." >&2; exit 1; }
# Reject characters that could alter the generated Ruby formula.
case "$1" in *\"*|*\\*|*\#*|*$'\n'*|*$'\r'*) echo "Unsupported URL characters" >&2; exit 1;; esac
checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"
mkdir -p dist/Casks
cat > dist/Casks/fdm.rb <<CASK
cask "fdm" do
  version "0.16.8"
  sha256 "$checksum"
  url "$1"
  name "fdm"
  desc "Compact desktop metronome with tap tempo and beat accents"
  homepage "${1%/*}"
  depends_on macos: ">= :ventura"
  app "fdm.app"
end
CASK
echo "Created dist/Casks/fdm.rb for the archive built on this Mac."

