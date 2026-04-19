#!/usr/bin/env bash
set -euo pipefail

SCHEME="${1:-PiliPlusNative}"
ARCHIVE_PATH="${2:-$PWD/build/${SCHEME}.xcarchive}"
IPA_PATH="${3:-$PWD/build/${SCHEME}-unsigned.ipa}"

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' | head -n 1)"

if [[ -z "${APP_PATH}" ]]; then
  echo "No .app found inside archive: $ARCHIVE_PATH"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
PAYLOAD_DIR="$WORK_DIR/Payload"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"

pushd "$WORK_DIR" >/dev/null
/usr/bin/zip -qry "$IPA_PATH" Payload
popd >/dev/null

rm -rf "$WORK_DIR"
echo "Created unsigned IPA at $IPA_PATH"

