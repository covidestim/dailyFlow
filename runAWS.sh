#!/usr/bin/bash

JOBNAME="$(date '+%Y-%m-%d')"
JOBQUEUE="highpriority-335bde00-db1b-11ea-9c54-02848c93abf4"

# Targets AWS Batch
aws batch submit-job \
  --job-name $JOBNAME \
  --job-queue $JOBQUEUE \
  --job-definition nextflow \
  --container-overrides command=covidestim/dailyFlow,\
"-latest",\
"-profile","amazon,counties",\
"--branch","SplinesRt",\
"--key","fips",\
"--outdir","s3://nf-test-results/$JOBNAME",\
"--date","$JOBNAME"
