#!/usr/bin/bash

# Targets AWS Batch
aws batch submit-job \
  --job-name SplinesRt-test1 \
  --job-queue "highpriority-335bde00-db1b-11ea-9c54-02848c93abf4" \
  --job-definition nextflow \
  --container-overrides command=covidestim/dailyFlow,\
"-r","SplinesRt","-profile","amazon"
