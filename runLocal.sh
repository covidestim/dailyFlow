#!/usr/bin/env bash
#SBATCH --time=720
#SBATCH --mail-user=marcus.russi@yale.edu
#SBATCH --mail-type=ALL

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
branch="ifr-frozen"
key=state

# Targets YCRC/Grace
nextflow run covidestim/dailyFlow \
  -r "ifr" \
  --s3pub false \
  -latest \
  -profile "local,states" \
  -N "marcus.russi@yale.edu" \
  --branch $branch \
  --key $key \
  --outdir "s3://nf-test-results/ifr-state-$date" \
  --date $date \
  --PGCONN "$(cat SECRET_RDS_CREDENTIALS)"
