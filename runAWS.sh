#!/usr/bin/env bash

# This script is for TESTING ONLY. In particular, the following changes should
# be made when transitioning from testing to production:
#
# - BRANCH should be modified
# - the "-r" flag should be modified
# - "--s3pub" should be removed (which will re-enable it due to nextflow.config)
# - `nextflow.config` should be thoroughly examined
# - "--outdir" should be changed to remove the 'ifr-' prefix

JOBNAME="$(date '+%Y-%m-%d')"
JOBQUEUE="highpriority-335bde00-db1b-11ea-9c54-02848c93abf4"
BRANCH="ifr-frozen"

# Targets AWS Batch
aws batch submit-job \
  --job-name $JOBNAME \
  --job-queue $JOBQUEUE \
  --job-definition nextflow \
  --container-overrides command=covidestim/dailyFlow,\
"-r","ifr",\
"--s3pub","false",\
"-latest",\
"-profile","amazon,counties",\
"-N","marcus.russi@yale.edu",\
"--branch","$BRANCH",\
"--key","fips",\
"--outdir","s3://nf-test-results/ifr-fips-$JOBNAME",\
"--date","$JOBNAME"
