#!/usr/bin/env bash
export NXF_ENABLE_SECRETS=true

# NOTE: Execute this from the repository root.

branch="latest"
key=fips
date=$(date +%Y-%m-%d)

nextflow run . \
  --key $key -profile "counties,local_prod,api_prod" \
  --branch $branch \
  --outdir $date \
  --date $date 
