#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build the Lambda artefacts using AWS SAM and copy the resulting ZIPs to the
# locations Terraform expects.
#
# Prereqs:
#   • AWS SAM CLI v1.107+
#   • Docker running if you build with --use-container
# -----------------------------------------------------------------------------
set -euo pipefail

TEMPLATE="template-sam.yaml"
CURRENT_DIR=$(pwd)
OUT_DIR="lambdas" # where Terraform looks for the final zips

echo "==> SAM build (containerised) ..."
sam build --template "$TEMPLATE" --use-container

# Function name -> target zip mapping
declare -A ZIP_MAP=(
  ["S3UploadFunction"]="s3_upload.zip"
  ["CatStatusFunction"]="cat_status.zip"
)

for FN in "${!ZIP_MAP[@]}"; do
  cd .aws-sam/build/$FN/ && zip $CURRENT_DIR/$OUT_DIR/${ZIP_MAP[$FN]} -q -r * && cd $CURRENT_DIR
  echo "-> ${ZIP_MAP[$FN]} created"
done

echo "==> Done. Terraform can now pick up the fresh ZIPs."
