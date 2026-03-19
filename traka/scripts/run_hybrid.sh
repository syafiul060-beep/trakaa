#!/bin/bash
# Run Flutter Traka dengan mode hybrid (development)
# Usage: ./scripts/run_hybrid.sh [API_URL]

API_URL="${1:-https://trakaa-production.up.railway.app}"
API_URL="${API_URL%/}"

echo "Running Traka Hybrid - API: $API_URL"

# Baca MAPS_API_KEY dari key.properties (untuk Directions API & peta)
MAPS_KEY=""
if [ -f android/key.properties ]; then
  MAPS_KEY=$(grep "^MAPS_API_KEY=" android/key.properties 2>/dev/null | cut -d= -f2- | tr -d '\r')
fi

if [ -n "$MAPS_KEY" ]; then
  flutter run --dart-define=TRAKA_API_BASE_URL=$API_URL --dart-define=TRAKA_USE_HYBRID=true --dart-define=MAPS_API_KEY=$MAPS_KEY
else
  echo "WARNING: MAPS_API_KEY tidak ditemukan di android/key.properties. Rute/peta mungkin gagal."
  flutter run --dart-define=TRAKA_API_BASE_URL=$API_URL --dart-define=TRAKA_USE_HYBRID=true
fi
