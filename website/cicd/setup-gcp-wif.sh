#!/usr/bin/env bash
# One-time setup for GitHub Actions → GCS push via Workload Identity
# Federation. Mirrors the pattern used by the personal blog repo
# (gha-push-gcs-blog) — same project, same WI pool, new service account
# scoped to the Claude Status website bucket.
#
# Run on a workstation with gcloud authenticated to the GCP project owner.
# Steps marked "(idempotent)" can be re-run safely; pool/provider creates
# will warn if they already exist.

set -euo pipefail

# ── Inputs ────────────────────────────────────────────────────────────
PROJECT_ID="personal-218506"
SA_NAME="gha-push-gcs-claudestatus"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
BUCKET="claudestatus.runlocal.dev"
LOCATION="europe-west1"                        # adjust if you want EU/asia
WI_POOL="gitops-pool"                      # reused from the blog
WI_PROVIDER="gh-provider"                  # reused from the blog
GH_REPO_OWNER="bcollard"
GH_REPO_NAME="claude-status-macos-menu-bar"
BUCKET_ROLE="projects/${PROJECT_ID}/roles/claudecodebucketadmin"   # reused custom role

echo "→ Project: ${PROJECT_ID}"
echo "→ Bucket:  gs://${BUCKET}  (will be created if missing)"
echo "→ SA:      ${SA_EMAIL}"
echo "→ Repo:    github.com/${GH_REPO_OWNER}/${GH_REPO_NAME}"
echo

gcloud config configurations activate perso >/dev/null
# gcloud config set project "${PROJECT_ID}"

# --- o. Create role similar to wsvbucketadmin ───────────────────────────────
# (If you already have a bucket-admin role that grants these permissions, skip this.)
if ! gcloud iam roles describe "claudecodebucketadmin" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "→ Creating custom role ${BUCKET_ROLE}"
  gcloud iam roles create "claudecodebucketadmin" --project="${PROJECT_ID}" \
    --title="Claude Status bucket admin" \
    --permissions="storage.buckets.get,storage.buckets.update,storage.objects.create,storage.objects.delete,storage.objects.get,storage.objects.list" \
    --stage=GA
else
  echo "✓ Custom role ${BUCKET_ROLE} already exists (reusing)"
fi

# ── 1. Service account (idempotent) ───────────────────────────────────
if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "→ Creating service account ${SA_NAME}"
  gcloud iam service-accounts create "${SA_NAME}" \
    --project "${PROJECT_ID}" \
    --display-name "GHA pusher · Claude Status website"
else
  echo "✓ Service account ${SA_NAME} already exists"
fi

# ── 2. Grant bucket-admin custom role ─────────────────────────────────
echo "→ Granting bucket-admin role to ${SA_NAME}"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role "${BUCKET_ROLE}" \
  --condition=None \
  --quiet >/dev/null

# ── 3. Create the website bucket (idempotent) ─────────────────────────
if ! gcloud storage buckets describe "gs://${BUCKET}" >/dev/null 2>&1; then
  echo "→ Creating bucket gs://${BUCKET}"
  gcloud storage buckets create "gs://${BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${LOCATION}" \
    --uniform-bucket-level-access
else
  echo "✓ Bucket gs://${BUCKET} already exists"
fi

# Public read for static hosting.
echo "→ Making bucket world-readable"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member="allUsers" --role="roles/storage.objectViewer" --quiet >/dev/null

# Static-website configuration: serve index.html at /, 404.html on misses.
echo "→ Configuring website main page + 404"
gcloud storage buckets update "gs://${BUCKET}" \
  --web-main-page-suffix="index.html" \
  --web-error-page="404.html"

# ── 4. Workload Identity Pool (idempotent — likely already exists) ────
if ! gcloud iam workload-identity-pools describe "${WI_POOL}" \
       --project="${PROJECT_ID}" --location="global" >/dev/null 2>&1; then
  echo "→ Creating Workload Identity pool ${WI_POOL}"
  gcloud iam workload-identity-pools create "${WI_POOL}" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --display-name="Personal GitOps pool"
else
  echo "✓ WI pool ${WI_POOL} already exists (reusing)"
fi

POOL_ID=$(gcloud iam workload-identity-pools describe "${WI_POOL}" \
  --project="${PROJECT_ID}" --location="global" \
  --format="value(name)")

# ── 5. OIDC provider for GitHub (idempotent) ──────────────────────────
if ! gcloud iam workload-identity-pools providers describe "${WI_PROVIDER}" \
       --project="${PROJECT_ID}" --location="global" \
       --workload-identity-pool="${WI_POOL}" >/dev/null 2>&1; then
  echo "→ Creating OIDC provider ${WI_PROVIDER}"
  gcloud iam workload-identity-pools providers create-oidc "${WI_PROVIDER}" \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WI_POOL}" \
    --display-name="GitHub provider" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --issuer-uri="https://token.actions.githubusercontent.com"
else
  echo "✓ OIDC provider ${WI_PROVIDER} already exists (reusing)"
fi

# ── 6. Bind the SA to allow impersonation by this repo ────────────────
echo "→ Allowing repo ${GH_REPO_OWNER}/${GH_REPO_NAME} to impersonate ${SA_NAME}"
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_ID}/attribute.repository/${GH_REPO_OWNER}/${GH_REPO_NAME}" \
  --condition=None \
  --quiet >/dev/null

PROVIDER_ID=$(gcloud iam workload-identity-pools providers describe "${WI_PROVIDER}" \
  --project="${PROJECT_ID}" --location="global" \
  --workload-identity-pool="${WI_POOL}" \
  --format="value(name)")

echo
echo "✓ Setup complete."
echo
echo "── For the GitHub Actions workflow ─────────────────────────────"
echo "workload_identity_provider: ${PROVIDER_ID}"
echo "service_account:            ${SA_EMAIL}"
echo "bucket:                     gs://${BUCKET}"
echo
echo "Next:"
echo "  1. Point DNS for ${BUCKET} → c.storage.googleapis.com (CNAME)"
echo "     (Apex domains need a load-balancer-fronted bucket — see GCP docs.)"
echo "  2. Push to main; the deploy-website.yaml workflow will publish."
