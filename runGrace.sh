#!/usr/bin/bash
#SBATCH --time=720
#SBATCH --mail-user=marcus.russi@yale.edu
#SBATCH --mail-type=ALL

date="$(date '+%Y-%m-%d')"
branch=SplinesRt
key=state

module load awscli

# Targets YCRC/Grace
nextflow run covidestim/dailyFlow \
  -latest \
  -profile "slurm,states" \
  -N "marcus.russi@yale.edu" \
  --branch $branch \
  --key $key \
  --outdir "$date-$branch-$key" \
  --raw \
  --date $date
