#!/usr/bin/bash

# Targets AWS Batch
aws batch submit-job \
  --job-name "$(date '+%Y-%m-%d')" \
  --job-queue "highpriority-335bde00-db1b-11ea-9c54-02848c93abf4" \
  --job-definition nextflow \
  --container-overrides command=covidestim/dailyFlow,\
"-profile","amazon","--branch","countymodel","--key","fips",\
"--outdir","s3://nf-test-results/$(date '+%Y-%m-%d')"
