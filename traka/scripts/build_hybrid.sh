#!/bin/bash
# Build Flutter Traka dengan mode hybrid (Phase 1)
# Usage: ./scripts/build_hybrid.sh https://traka-api.example.com [apk|appbundle|ios]

API_URL="${1:?Usage: $0 <API_URL> [apk|appbundle|ios]}"
TARGET="${2:-apk}"

# Remove trailing slash
API_URL="${API_URL%/}"

echo "Building Traka Hybrid - API: $API_URL"

DART_DEFINES="--dart-define=TRAKA_API_BASE_URL=$API_URL --dart-define=TRAKA_USE_HYBRID=true"

case "$TARGET" in
  apk)       flutter build apk $DART_DEFINES ;;
  appbundle) flutter build appbundle $DART_DEFINES ;;
  ios)       flutter build ios $DART_DEFINES ;;
  *)         echo "Unknown target: $TARGET"; exit 1 ;;
esac
