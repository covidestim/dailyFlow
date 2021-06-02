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

## FAQ

**How do I change the number of attempts, and their length?**

Change `nextflow.config` by modifying `testFast`, `states`, `statesAggressive`, or `counties` to have a different value for `params.time`. Alternatively, write your own profile in addition to the ones mentioned above.

**How do I change how Stan is invoked?**

The `covidestim::covidestim()` function takes several argument which are passed to `rstan::sampling()`, such as `max_treedepth` and `adapt_delta`. If the parameter you wish to modify is an argument of `covidestim::covidestim()`, then modify `src/modelrunners.nf` so that that the function is called differently. If it's *not* an argument, change how `covidestim::run()` is called, because it uses dots (`...`) syntax, which is passed on to `rstan::sampling()`.

**How do I pass made-up case/death data to the model?**

This workflow was never built to support that; either write your own process definition, or run the model manually.

**How do I run using a different version of the model?**

Invoke the `--branch` flag when issuing the `nextflow run` command in the terminal. `<branch>` must be the name of a tag which exists on [Docker Hub](https://hub.docker.com/r/covidestim/covidestim). If there doesn't exist a container (tag) for that branch or tag, you'll need to push a new branch or tag to `covidestim/covidestim`, and then set up a rule in Docker Hub so that it auto-builds that branch or tag. You need special privileges to set these rules.

Beware that Singularity, which (basically) executes these containers in YCRC envionments, caches containers. If you push a new commit, and Docker Hub builds it, the cache will not invalidate and subsequently update the relevant container. `rm -rf work/singularity` will solve this.

**What other customizations are available?**

There are various arguments defined in `main.nf` which are invoked at runtime in the CLI (`nextflow run --arg1 val1 --arg2 val2 ...`). You can:

- `--testtracts`: Only run the "test tracts," a selection of ~300 counties and states
  
- `--PGCONN <conn>`: Specify the connection to the production results database, if you have it
  
- `--timemachine <date:YYYY-MM-DD>`: Run the model using archived data from a particular day
  
- `--alwaysoptimize`: Always use BFGS
  
- `--alwayssample`: Always sample, never fallback to BFGS
  
- `--n <number>`: Run the first `n` counties or states (in no particular order)
  
- `--branch <tag>`: Use the Docker Hub container with tag = `<tag>` when running the model
  
- `--key <state|fips>`: **IMPORTANT: must be specified at runtime**
  
- `--s3pub`: Publish results to AWS S3, only works if credentialed
  

## File structure/Processes

The file structure is as follows:

- `main.nf`: The workflow
- `src/*.nf`: All of the Nextflow ["processes"](https://www.nextflow.io/docs/edge/process.html)
- `nextflow.config`: [Nextflow configuration](https://www.nextflow.io/docs/edge/config.html) for different execution environments (YCRC/AWS Batch) and levels of geography (counties/states)
- `runAWS.sh`: Starts an all-county run on AWS Batch. Runs at 1:00am EDT to line up with the typical 12:50am EDT [JHU commit](https://github.com/CSSEGISandData/COVID-19/commits/master/csse_covid_19_data/csse_covid_19_time_series)
- `runGrace.sh`: Starts an all-state run on YCRC's Grace cluster. Also runs at 1:00am EDT daily.
- `s3-pack-push.sh`: The Nextflow workflow will place daily output files in the `s3://covidestim/stage/` prefix (directory). This script copies them to the `s3://covidestim/latest` directory, and makes them public, which effectively updates the website.

### `main.nf`

Specifies the main workflow and the default Nextflow parameters. The main workflow selects a process to generate model input data (counties = `jhuData`, states = `jhuStateData`), and connects the output of the selected process to the rest of the pipeline. The main workflow emits the following values:

- `summary`, a CSV of all model summaries
  
- `warning`, a CSV of all warnings from all model runs
  
- `optvals`, a CSV of the log-posteriors of all model runs performed using the BFGS algorithm
  
- `rejects`, a CSV of all counties or states which were rejected due to input data issues
  

`main.nf` references several processes which are defined in the `src/` directory: `jhuData`, `jhuStateData`, `runTractSampler`, `runTractOptimizer`, and auxillary processes `filterTestTracts`, `splitTractData`, `publishCountyResults`, `publishStateResults`.

### `runYCRC-state.sh`/`runYCRC-counties.sh`

Example Bash scripts for running the model on a SLURM-based cluster

### process `jhuData`

This is identical to `ctpData`, except that it cleans Johns Hopkins CSSE data at the county level. Since `covidestim-sources` references the JHU Git repo as a submodule, there are additional Git commands to bring the JHU submodule up to its `HEAD` commit on `origin/master`.

### process `splitTractData`

The cleaned input file is split by FIPS code or state name in preparation for being sent to `runTract`

### process `runTractSampler`

Runs the model for every county or state. The bulk of this process's definition is a short R script that reads the input data and performs the run. Note that when an RStan `treedepth` warning is present, the R script errors, which forces a rerun. Up to two reruns are allowed, as an attempt to catch counties or states that struggle to fit well, or fit within their timelimit. Raw (`RDS`) output can be saved if `params.raw` is set to `true`.

Each county or state gets a certain number of tries to produce good results. This is set my `params.time`. On the last try, if the sampler has thus far failed to produce a good result, BFGS is run, and an optimized result is returned, rather than a sampled one.

### process `runTractOptimizer`

Similar to `runTractSampler`, but always uses the BFGS optimizer.

### process `publishCountyResults` / `publishStateResults`

Creates county/state results that are suitable for distribution online by gzipping the `summary.csv` file that results from a state or county run, and by creating the WebPack file that the website consumes. These files are copied out to AWS S3.
