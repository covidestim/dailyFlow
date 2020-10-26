#!/usr/bin/bash

JOBNAME="$(date '+%Y-%m-%d')"
JOBQUEUE="highpriority-335bde00-db1b-11ea-9c54-02848c93abf4"
BRANCH="SplinesRt_unstable"

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
"--branch","$BRANCH",\
"--key","fips",\
"--outdir","s3://nf-test-results/$JOBNAME",\
"--date","$JOBNAME"
