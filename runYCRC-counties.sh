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
branch="immunity"
key=fips

module load awscli

# Targets YCRC/Grace
nextflow run . \
  --s3pub false \
  --ngroups 150 \
  -profile "slurm,counties,farnam" \
  -N "marcus.russi@yale.edu" \
  --branch $branch \
  --raw false \
  --key $key \
  --outdir v0 \
  --date $date
