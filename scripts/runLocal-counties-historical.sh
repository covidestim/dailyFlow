#!/usr/bin/env bash
export NXF_ENABLE_SECRETS=true

# NOTE: Execute this from the repository root.

branch="latest"
key=fips

nextflow run . \
  -profile "local,counties,api_prod" \
  --raw false\
  --s3pub false \
  --branch $branch \
  --key $key \
  --outdir historical/$2 \
  --input-url "https://covidestim.s3.amazonaws.com/inputs-for-prerelease-historical-runs/historical-fips-$1-weeks-back.tar.gz" \
  --date $2
