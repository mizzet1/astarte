#!/bin/bash
set -e

echo "Building and tagging all Astarte images for Kubernetes deployment..."
echo "Authentication is disabled by default in all services"

cd /home/rick/Desktop/astarte-dev/astarte

# Pull external images
echo "Pulling external images..."
docker pull astarte/vernemq:1.2-snapshot

# Build all Astarte services
echo "Building astarte-data-updater-plant..."
docker compose build astarte-data-updater-plant

echo "Building astarte-housekeeping..."
docker compose build astarte-housekeeping

echo "Building astarte-realm-management..."
docker compose build astarte-realm-management

echo "Building astarte-appengine-api..."
docker compose build astarte-appengine-api

echo "Building astarte-pairing..."
docker compose build astarte-pairing

echo "Building astarte-trigger-engine..."
docker compose build astarte-trigger-engine

# Tag all images for your repository
echo "Tagging images for mizzet1 repository..."
docker tag astarte/vernemq:1.2-snapshot mizzet1/vernemq:latest
docker tag astarte/astarte_data_updater_plant:1.2-snapshot mizzet1/astarte-data-updater-plant:latest
docker tag astarte/astarte_housekeeping:1.2-snapshot mizzet1/astarte-housekeeping:latest
docker tag astarte/astarte_realm_management:1.2-snapshot mizzet1/astarte-realm-management:latest
docker tag astarte/astarte_appengine_api:1.2-snapshot mizzet1/astarte-appengine-api:latest
docker tag astarte/astarte_pairing:1.2-snapshot mizzet1/astarte-pairing:latest
docker tag astarte/astarte_trigger_engine:1.2-snapshot mizzet1/astarte-trigger-engine:latest
docker tag astarte/astarte-dashboard:1.2-snapshot mizzet1/astarte-dashboard:latest

# Push all images to Docker Hub
echo "Pushing images to Docker Hub..."
docker push mizzet1/vernemq:latest
docker push mizzet1/astarte-data-updater-plant:latest
docker push mizzet1/astarte-housekeeping:latest
docker push mizzet1/astarte-realm-management:latest
docker push mizzet1/astarte-appengine-api:latest
docker push mizzet1/astarte-pairing:latest
docker push mizzet1/astarte-trigger-engine:latest
docker push mizzet1/astarte-dashboard:latest

echo ""
echo "✅ All Astarte images built, tagged, and pushed successfully!"
echo ""
echo "Images available on Docker Hub:"
echo "- mizzet1/vernemq:latest"
echo "- mizzet1/astarte-data-updater-plant:latest"
echo "- mizzet1/astarte-housekeeping:latest"
echo "- mizzet1/astarte-realm-management:latest"
echo "- mizzet1/astarte-appengine-api:latest"
echo "- mizzet1/astarte-pairing:latest"
echo "- mizzet1/astarte-trigger-engine:latest"
echo "- mizzet1/astarte-dashboard:latest"
echo ""
echo "🔓 Authentication is DISABLED by default in all API services!"
echo "⚠️  Remember to enable authentication in production by setting:"
echo "   - HOUSEKEEPING_API_DISABLE_AUTHENTICATION=false"
echo "   - REALM_MANAGEMENT_API_DISABLE_AUTHENTICATION=false"
echo "   - APPENGINE_API_DISABLE_AUTHENTICATION=false"
echo "   - PAIRING_API_DISABLE_AUTHENTICATION=false"
