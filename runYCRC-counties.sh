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
branch="master"
key=fips

module load awscli

# Targets YCRC/Grace
nextflow run covidestim/dailyFlow \
  -r "master" \
  --s3pub true \
  -latest \
  --ngroups 150 \
  -profile "slurm,counties" \
  -N "marcus.russi@yale.edu" \
  --branch $branch \
  --raw false \
  --key $key \
  --outdir "s3://nf-test-results/$date" \
  --date $date \
  --PGCONN "$(cat SECRET_RDS_CREDENTIALS)"
