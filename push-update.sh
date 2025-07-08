#!/bin/bash

set -euo pipefail  # Stop on error, undefined vars, or failed pipes

eval $(minikube docker-env)

# -----------------------------
# Configuration
# -----------------------------

# TTL for ttl.sh images (1 day)
TTL="1d"

# Docker image namespace on ttl.sh
NAMESPACE="mizzet1/astarte"

# Full path to your Astarte deployment YAML
CR_FILE="/home/rick/Desktop/astarte-prometheus-grafana/terraform-minikube/astarte.yaml"

# Temporary patched file that will be applied to Minikube
TMP_PATCHED="/home/rick/Desktop/astarte-prometheus-grafana/terraform-minikube/astarte-patched.yaml"

# Map of Astarte service keys in the YAML → local Docker build folders
declare -A SERVICES=(
  ["dataUpdaterPlant"]="apps/astarte_data_updater_plant"
  ["realmManagement.backend"]="apps/astarte_realm_management"
)

# -----------------------------
# Build, tag, push, patch loop
# -----------------------------
echo "📦 Building and pushing images to ttl.sh..."

for key in "${!SERVICES[@]}"; do
  # Extract service name from folder (used in the image name)
  name=$(basename "${SERVICES[$key]}")
  tag="ttl.sh/$NAMESPACE/${name}:${TTL}"

  echo "🔨 Building image for $name from ${SERVICES[$key]}"
  docker build -t "$name" "${SERVICES[$key]}"

  echo "🏷️ Tagging image as $tag"
  docker tag "$name" "$tag"

  #echo "📤 Pushing image to ttl.sh"
  #docker push "$tag"

  echo "📝 Updating image reference in YAML for .spec.components.${key}.image → $tag"
  /home/linuxbrew/.linuxbrew/bin/yq eval --inplace ".spec.components.${key}.image = \"$tag\"" "$CR_FILE"

done

# Create a patched copy of the YAML for applying
echo "📄 Saving patched YAML to $TMP_PATCHED"
cp "$CR_FILE" "$TMP_PATCHED"

# -----------------------------
# Apply the updated YAML to Minikube
# -----------------------------
echo "🚀 Applying updated Astarte deployment to Minikube..."
kubectl apply -f "$TMP_PATCHED"

echo "✅ Done: Images built, pushed, YAML patched and applied to Minikube."
