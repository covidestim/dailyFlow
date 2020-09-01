#!/usr/bin/bash
#SBATCH --time=660
#SBATCH --mail-user=marcus.russi@yale.edu
#SBATCH --mail-type=ALL

# Targets YCRC/Grace
nextflow run covidestim/dailyFlow \
  -profile ycrc \
  -with-report report.html \
  -with-timeline timeline.html \
  -N "marcus.russi@yale.edu"
