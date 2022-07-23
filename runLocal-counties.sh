#!/usr/bin/env bash
export NXF_ENABLE_SECRETS=true

# This script is for TESTING ONLY. In particular, the following changes should
# be made when transitioning from testing to production:
#
# - BRANCH should be modified
#
# - "--s3pub" should be removed (which will re-enable it due to nextflow.config)
#
# - `nextflow.config` should be thoroughly examined
#
# - "--outdir" should be changed to use the local FS, look at an old commit
#   to find the exact syntax

date="$(date '+%Y-%m-%d')"
branch="schema"
key=fips

nextflow run . \
  -profile "local,counties,db_local" \
  $@ \
  --ngroups 4000 \
  --raw false\
  --s3pub false \
  --branch $branch \
  --key $key \
  --outdir test-$(date +%Y-%m-%d)-counties \
  --input-url "https://covidestim.s3.amazonaws.com/inputs-for-prerelease-historical-runs/historical-fips-11-weeks-back.tar.gz" \
  --date $date
