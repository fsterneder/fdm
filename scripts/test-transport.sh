#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
transport_binary="$(mktemp -t fdm-transport.XXXXXX)"
trap 'rm -f "$transport_binary"' EXIT
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror \
  -I Sources/RealtimeAudio/include \
  Sources/RealtimeAudio/RealtimeAudio.c Tests/RealtimeAudioTests/transport_test.c \
  -lm -pthread -o "$transport_binary"
"$transport_binary"

