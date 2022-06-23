#!/usr/bin/env bash
#SBATCH --time=720
#SBATCH --mail-user=marcus.russi@yale.edu
#SBATCH --mail-type=ALL

export NXF_ENABLE_SECRETS=true

# This script is for TESTING ONLY. In particular, the following changes should
# be made when transitioning from testing to production:
#
# - BRANCH should be modified
#
# - the "-r" flag should be modified
#
# - "--s3pub" should be removed (which will re-enable it due to nextflow.config)
#
# - `nextflow.config` should be thoroughly examined
#
# - "-outdir" should be changed to use the local FS, look at an old commit
#   to find the exact syntax

date="$(date '+%Y-%m-%d')"
branch="schema"
key=state

nextflow run . \
  -profile "local,states,db_local" \
  $@ \
  --s3pub false \
  --branch $branch \
  --key $key \
  --outdir SCHEMA_TEST3_STATES \
  --date $date

nextflow run . \
  -profile "local,counties,db_local" \
  $@ \
  --ngroups 150 \
  --raw false\
  --s3pub false \
  --branch $branch \
  --key fips \
  --outdir SCHEMA_TEST3_COUNTIES \
  --date $date
