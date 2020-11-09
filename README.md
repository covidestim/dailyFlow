# dailyFlow

This repository contains a Nextflow workflow used to orchestrate state- and county-level runs on AWS Batch and the Yale Center for Research Computing clusters. The workflow takes care of the following steps:

- Acquiring and cleaning input cases and death data for all counties and states
- Performing a model run for each county or state using said input data
- Combining all of these results together to create various representations, inluding the WebPack file served to the browser
- Making the results available on AWS S3, where they eventually are manually reviewed and made available on the public-facing website

Nextflow takes care of:

- Managing the various Singularity (YCRC) and Docker (AWS Batch/ECR) containers that are used for these operations
- Passing data between tasks
- Producing logs of what happened
- Automatic retry when model runs timeout or fail

The file structure is as follows:

- `main.nf`: The workflow, containing all of the Nextflow ["processes"](https://www.nextflow.io/docs/edge/process.html)
- `nextflow.config`: [Nextflow configuration](https://www.nextflow.io/docs/edge/config.html) for different execution environments (YCRC/AWS Batch) and levels of geography (counties/states)
- `runAWS.sh`: Starts an all-county run on AWS Batch. Runs at 1:00am EDT to line up with the typical 12:50am EDT [JHU commit](https://github.com/CSSEGISandData/COVID-19/commits/master/csse_covid_19_data/csse_covid_19_time_series)
- `runGrace.sh`: Starts an all-state run on YCRC's Grace cluster. Also runs at 1:00am EDT daily.
- `s3-pack-push.sh`: The Nextflow workflow will place daily output files in the `s3://covidestim/stage/` prefix (directory). This script copies them to the `s3://covidestim/latest` directory, and makes them public, which effectively updates the website.

## `main.nf`

### process `ctpData`

Using an R container, [`covidestim-sources/makefile`](https://github.com/covidestim/covidestim-sources/blob/master/makefile) is run to pull and clean Covid Tracking Project data at the state level. One retry is allowed in case of HTTP error.

### process `jhuData`

This is identical to `ctpData`, except that it cleans Johns Hopkins CSSE data at the county level. Since `covidestim-sources` references the JHU Git repo as a submodule, there are additional Git commands to bring the JHU submodule up to its `HEAD` commit on `origin/master`.

### process `splitTractData`

The cleaned input file is split by FIPS code or state name in preparation for being sent to `runTract`

### process `runTract`

Runs the model for every county or state. The bulk of this process's definition is a short R script that reads the input data and performs the run. Note that when an RStan `treedepth` warning is present, the R script errors, which forces a rerun. Up to two reruns are allowed, as an attempt to catch counties or states that struggle to fit well, or fit within their timelimit. Raw (`RDS`) output can be saved if `params.raw` is set to `true`.

### process `publishCountyResults` / `publishStateResults`

Creates county/state results that are suitable for distribution online by gzipping the `summary.csv` file that results from a state or county run, and by creating the WebPack file that the website consumes. These files are copied out to AWS S3.
