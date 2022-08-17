#!/usr/bin/env bash
export NXF_ENABLE_SECRETS=true

# NOTE: Execute this from the repository root.

date="$(date '+%Y-%m-%d')"
branch="latest"
key=state

nextflow run . \
  -profile "local,states,api_local" \
  $@ \
  --branch $branch \
  --key $key \
  --outdir test-$(date +%Y-%m-%d)-states \
  --date $date
