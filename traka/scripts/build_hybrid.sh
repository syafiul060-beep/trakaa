#!/bin/bash
# Build Flutter Traka dengan mode hybrid (Phase 1)
# Usage: ./scripts/build_hybrid.sh [API_URL] [apk|appbundle|ios]
# Default API: https://trakaa-production.up.railway.app

DEFAULT_URL="https://trakaa-production.up.railway.app"
case "$1" in
  apk|appbundle|ios) API_URL="$DEFAULT_URL"; TARGET="$1" ;;
  "")                API_URL="$DEFAULT_URL"; TARGET="apk" ;;
  *)                 API_URL="$1";          TARGET="${2:-apk}" ;;
esac

# Remove trailing slash
API_URL="${API_URL%/}"

echo "Building Traka Hybrid - API: $API_URL"

# Baca MAPS_API_KEY dari key.properties (untuk Directions API)
MAPS_KEY=""
if [ -f android/key.properties ]; then
  MAPS_KEY=$(grep "^MAPS_API_KEY=" android/key.properties 2>/dev/null | cut -d= -f2- | tr -d '\r')
fi
if [ -n "$MAPS_KEY" ]; then
  DART_DEFINES="--dart-define=TRAKA_API_BASE_URL=$API_URL --dart-define=TRAKA_USE_HYBRID=true --dart-define=MAPS_API_KEY=$MAPS_KEY"
else
  DART_DEFINES="--dart-define=TRAKA_API_BASE_URL=$API_URL --dart-define=TRAKA_USE_HYBRID=true"
fi

case "$TARGET" in
  apk)       flutter build apk $DART_DEFINES ;;
  appbundle) flutter build appbundle $DART_DEFINES ;;
  ios)       flutter build ios $DART_DEFINES ;;
  *)         echo "Unknown target: $TARGET"; exit 1 ;;
esac
