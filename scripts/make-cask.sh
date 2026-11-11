#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 || ! "$1" =~ ^https:// ]]; then
  echo "Usage: bash scripts/make-cask.sh https://HOST/path/fdm-3-0.8.2.zip" >&2
  exit 1
fi
archive="dist/fdm-3-0.8.2.zip"
[[ -f "$archive" ]] || { echo "Run scripts/build.sh first." >&2; exit 1; }
# Reject characters that could alter the generated Ruby formula.
case "$1" in *\"*|*\\*|*\#*|*$'\n'*|*$'\r'*) echo "Unsupported URL characters" >&2; exit 1;; esac
checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"
mkdir -p dist/Casks
cat > dist/Casks/fdm-3.rb <<CASK
cask "fdm-3" do
  version "0.8.2"
  sha256 "$checksum"
  url "$1"
  name "fdm-3"
  desc "Compact desktop metronome with tap tempo and beat accents"
  homepage "${1%/*}"
  depends_on macos: ">= :ventura"
  app "fdm-3.app"
end
CASK
echo "Created dist/Casks/fdm-3.rb for the archive built on this Mac."
