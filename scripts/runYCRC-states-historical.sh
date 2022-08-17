#!/usr/bin/env bash
#SBATCH --time=720
#SBATCH --mail-user=marcus.russi@yale.edu
#SBATCH --mail-type=ALL
export NXF_ENABLE_SECRETS=true

# NOTE: Execute this from the repository root.

branch="latest"
key=state

module load awscli

nextflow run . \
  -profile "slurm,states,api_prod" \
  -N "marcusrussi@gmail.com" \
  --s3pub false \
  --raw false\
  --branch $branch \
  --key $key \
  --outdir historical/$2 \
  --input-url "https://covidestim.s3.amazonaws.com/inputs-for-prerelease-historical-runs/historical-state-$1-weeks-back.tar.gz" \
  --date $2
