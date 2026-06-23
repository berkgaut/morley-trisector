#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
AWS_PROFILE="${AWS_PROFILE:-berkgaut}"
DEPLOY_TAG_KEY="Deployment"
DEPLOY_TAG_VALUE="berkgaut.tools"
S3_PREFIX="other/projects/cc/26.26/morleys-trisector"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"   # directory containing this script

# ── Resolve S3 bucket by tag ───────────────────────────────────────────────────
echo "Resolving S3 bucket tagged ${DEPLOY_TAG_KEY}=${DEPLOY_TAG_VALUE}..."
BUCKET=$(aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=${DEPLOY_TAG_KEY},Values=${DEPLOY_TAG_VALUE}" \
  --resource-type-filters "s3:bucket" \
  --region eu-north-1 \
  --profile "$AWS_PROFILE" \
  --query "ResourceTagMappingList[0].ResourceARN" \
  --output text | sed 's|arn:aws:s3:::||')

if [[ -z "$BUCKET" || "$BUCKET" == "None" ]]; then
  echo "ERROR: no S3 bucket found with tag ${DEPLOY_TAG_KEY}=${DEPLOY_TAG_VALUE}" >&2
  exit 1
fi
echo "  bucket: $BUCKET"

# ── Resolve CloudFront distribution by tag ─────────────────────────────────────
# CloudFront is a global service; its tags are only visible from us-east-1
echo "Resolving CloudFront distribution tagged ${DEPLOY_TAG_KEY}=${DEPLOY_TAG_VALUE}..."
DISTRIBUTION_ARN=$(aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=${DEPLOY_TAG_KEY},Values=${DEPLOY_TAG_VALUE}" \
  --resource-type-filters "cloudfront:distribution" \
  --region us-east-1 \
  --profile "$AWS_PROFILE" \
  --query "ResourceTagMappingList[0].ResourceARN" \
  --output text)

if [[ -z "$DISTRIBUTION_ARN" || "$DISTRIBUTION_ARN" == "None" ]]; then
  echo "ERROR: no CloudFront distribution found with tag ${DEPLOY_TAG_KEY}=${DEPLOY_TAG_VALUE}" >&2
  exit 1
fi
DISTRIBUTION_ID="${DISTRIBUTION_ARN##*/}"
echo "  distribution: $DISTRIBUTION_ID"

# ── Copy files to S3 ──────────────────────────────────────────────────────────
echo "Uploading ${SOURCE_DIR} → s3://${BUCKET}/${S3_PREFIX}/ ..."
aws s3 cp "$SOURCE_DIR/index.html" "s3://${BUCKET}/${S3_PREFIX}/"
echo "  upload complete."

# ── Create CloudFront invalidation and wait ────────────────────────────────────
INVALIDATION_PATH="/${S3_PREFIX}/*"
echo "Creating invalidation for ${INVALIDATION_PATH} ..."
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "$INVALIDATION_PATH" \
  --profile "$AWS_PROFILE" \
  --query "Invalidation.Id" \
  --output text)
echo "  invalidation id: $INVALIDATION_ID"

echo "Waiting for invalidation to complete (this may take a minute)..."
aws cloudfront wait invalidation-completed \
  --distribution-id "$DISTRIBUTION_ID" \
  --id "$INVALIDATION_ID" \
  --profile "$AWS_PROFILE"
echo "  invalidation complete."

echo ""
echo "Deployment done."
echo "  https://dlz7d8tl3feij.cloudfront.net/${S3_PREFIX}/"
