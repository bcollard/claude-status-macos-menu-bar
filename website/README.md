# claudestatus.runlocal.dev

Single-page marketing site for the Claude Status macOS menu-bar app.
Hand-rolled HTML/CSS — no SSG, no framework, no JS dependencies. Served
as static files from a Google Cloud Storage bucket.

## Local preview

```bash
cd website
python3 -m http.server 8765
# open http://localhost:8765/
```

## Deploy

Pushes to `main` that touch `website/**` trigger
`.github/workflows/deploy-website.yaml`, which authenticates via Workload
Identity Federation and runs `gsutil rsync` into
`gs://claudestatus.runlocal.dev`.

## One-time GCP setup

```bash
./website/cicd/setup-gcp-wif.sh
```

Creates (or updates idempotently):

- Service account `gha-push-gcs-claudestatus@personal-218506`
- Bucket `gs://claudestatus.runlocal.dev` with website hosting + public read
- WIF binding allowing this GitHub repo to impersonate the SA

You still need to point DNS for `claudestatus.runlocal.dev` at GCS once
the bucket is up. For an apex domain you'll likely want a
Cloud-Load-Balancer-fronted bucket (`gcloud compute backend-buckets`) so
HTTPS works.

## Regenerating screenshots

```bash
./scripts/screenshots.sh
```

Produces both the App-Store marketing canvases (under `docs/screenshots/`)
and the website's transparent popup + settings cards (under
`website/assets/`).
