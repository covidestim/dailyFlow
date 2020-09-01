#!/usr/bin/bash
#SBATCH --time=660
#SBATCH --mail-user=marcus.russi@yale.edu
#SBATCH --mail-type=ALL

date="$(date '+%Y-%m-%d')"
branch=SplinesRt
key=state

# Targets YCRC/Grace
nextflow run covidestim/dailyFlow \
  -latest \
  -profile slurm \
  -N "marcus.russi@yale.edu" \
  --branch $branch \
  --key $key \
  --outdir "$date-$branch-$key" \
  --raw
