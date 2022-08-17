# dailyFlow

This repository contains a Nextflow workflow used to orchestrate state- and county-level runs on AWS Batch and the Yale Center for Research Computing clusters. The workflow takes care of the following steps:

- Cleaning for all counties and states, using scripts from [`covidestim-sources`](https://github.com/covidestim/covidestim-sources).
- Performing a model run for each county or state using said input data
- Aggregating these results
- Making the results available to the public by inserting them into our database, and by generating static files used on our public website.

Nextflow:

- Manages and executes the Singularity (on YCRC) and Docker (local execution / AWS) containers that are used to run different scripts
- Passes data between different Nextflow processes
- Produces logs of what happened
- In certain situations, reruns models when they timeout or fail

## Workflow diagrams

### States

![State workflow](/images/states.drawio.png)

### Counties

![County workflow](/images/counties.drawio.png)

## Getting started

### Configuration

Install Nextflow at [nextflow.io](https://www.nextflow.io/). You need at least `21.09.0-edge` because we use the Secrets feature. Nextflow will take care of downloading all containers from [Docker Hub](https://hub.docker.com/u/covidestim) the first time you run this pipeline. Next, take note of the following configuration options. You'll want to use different configuration options depending on whether you're developing locally, testing on the cluster, or deploying production code.

**No API**

This is great for making changes to the pipeline that have nothing to do with persisting data.

| option         | value   |
| -------------- | ------- |
| `--insertApi`  | `false` |

**Local API**

You can easily spin up a local database and API by cloning [covidestim/db](https://github.com/covidestim/db) and running `docker-compose up` from the root of that repository. This will give you a database and API that matches our production schema.

To generate a JWT for your local API so that you can define the mandatory Nextflow Secret `COVIDESTIM_JWT`, follow steps 2 and 3 of [this PostgREST tutorial](https://postgrest.org/en/stable/tutorials/tut1.html#step-2-make-a-secret).

| option         | value   |
| -------------- | ------- |
| `-profile`     | `api_local` |
| Nextflow Secret `COVIDESTIM_JWT` | defined |

**Test API**

We run a test API server at https://api2-test.covidestim.org. Its schema is the same as the production database, but there is less model data stored in it. You'll need to generate or be provided a JWT token to insert runs via this API.

| option         | value   |
| -------------- | ------- |
| `-profile`     | `api_local` |
| Nextflow Secret `COVIDESTIM_JWT` | defined |

**Production API**

This is https://api2.covidestim.org. JWT token also must be generated or provided.

| option         | value   |
| -------------- | ------- |
| `-profile`     | `api_local` |
| Nextflow Secret `COVIDESTIM_JWT` | defined |

**Enabling dbstan integration**

Keep in mind that dbstan inserts take up a lot of space in the database, and we don't yet automatically delete old dbstan runs. Enabling the dbstan integration is not necessary to run the pipeline for test or production.

| option         | value   |
| -------------- | ------- |
| `-profile`     | `dbstan_enable` |
| Nextflow Secret `COVIDESTIM_DBSTAN_HOST` | defined, must be hostname of Postgres server on port 5432 |
| Nextflow Secret `COVIDESTIM_DBSTAN_DBNAME` | defined, Postgres db name |
| Nextflow Secret `COVIDESTIM_DBSTAN_USER` | defined, Postgres user, see [here](https://github.com/covidestim/dbstan/blob/master/init/init.sql) (`dbstan_writer`) |
| Nextflow Secret `COVIDESTIM_DBSTAN_PASS` | defined, Postgres user password |

### Runtime options

There are parameters defined in `main.nf` which can be invoked at runtime in the CLI (`nextflow run --arg1 val1 --arg2 val2 ...`). The available CLI options are:

**Required**

- `-profile`
  - Specify `states` or `counties`
  - Specify `local` or `slurm`
  - See **Configuration** section above for API/dbstan profiles.
- `--branch <tag>`: Use the Docker Hub container with tag = `<tag>` when running the model. Note that the Github branch `master` will exist as the Docker Hub container with tag = `latest`.
- `--key <state|fips>`: **IMPORTANT: must be specified at runtime**
-- `--date YYYY-MM-DD`: Sets the nominal "run date" for the run. Does not necessarily need to be the same as today's date.
  
**Optional**

- `--inputUrl <url>`: This bypasses the usual data-cleaning process, and instead passes premade input data to the instances of the model. `<url>` must be a `.tar.gz` file containing `data.csv`, `metadata.json`, and `rejects.csv`. These files must have the same schema as would be produced in the normal data-cleaning process, but need not contain all geographies.
- `--ngroups`: When you have more geographies to model than you have hourly submissions to the SLURM scheduler, set this to cause geographies to be batched together into processes that contain multiple geographies.
- `--raw`: This will save all `covidestim-result` objects to `.RDS` files, using the name of each geography as the filename, or the group id, if `--ngroups` is used.
- `--splicedate`: Deprecated.
- `--testtracts`: Only run the "test tracts," a selection of ~300 counties and states
- `--alwaysoptimize`: Always use BFGS
- `--alwayssample`: Always sample, never fallback to BFGS
- `--n <number>`: Run the first `n` counties or states (in no particular order)
- `--s3pub`: Publish results to AWS S3, only works if credentialed

### Examples

**County production run, local**

Run the county pipeline locally, inserting the results into the database, and
uploading static files to S3. Available in repository as
`scripts/runLocal-counties-prod.sh`.

```bash
#!/usr/bin/env bash
export NXF_ENABLE_SECRETS=true

# NOTE: Execute this from the repository root.

branch="latest"
key=fips
date=$(date +%Y-%m-%d)

nextflow run . \
  --key $key -profile "counties,local_prod,api_prod" \
  --branch $branch \
  --outdir $date \
  --date $date 
```

## FAQ

**How do I change the number of attempts, and their length?**

Change `nextflow.config` by modifying the `states` and `counties` profiles.

**How do I change how Stan is invoked?**

See [covidestim-batch](https://github.com/covidestim/covidestim/blob/master/exec/batch.R) for available CLI options. Otherwise, modify that script yourself, and rebuild a local `webworker` container so that Nextflow excecutes your modified script.

**How do I pass made-up case/death data to the model?**

Use the `--inputUrl` CLI flag. Alternatively, use the model outside the Nextflow workflow, which may be easier.

**How do I run using an updated or different version of the model? Or new version of the webworker container**

For running a custom model version, invoke the `--branch` flag when issuing the `nextflow run` command in the terminal. `<branch>` must be the name of a tag which exists on [Docker Hub](https://hub.docker.com/r/covidestim/covidestim). If there doesn't exist a container (tag) for that branch or tag, you'll need to push a new branch or tag to the GitHub remote at `covidestim/covidestim`, and then set up a rule in Docker Hub so that it auto-builds that branch or tag. You need special privileges to set these rules. You can also build a container locally, and push it to Docker Hub using `docker push`.

*Important*: For running a *new* model that is now the `HEAD` of the branch currently being used, you need to ensure that:

1. The new commit successfully pushed to `covidestim/covidestim`.
2. It was successfully built and tagged on Docker Hub (either autobuilt, or pushed to Docker Hub).
3. The local registry has the container. Locally, run `docker pull covidestim/covidestim:TAG`, and on the cluster, run `rm -rf work/singularity`, forcing Singularity to rebuilt the Docker Hub-sourced container the next time Nextflow executes.

## File structure/Processes

The file structure is as follows:

- `main.nf`: The workflow
- `src/*.nf`: All of the Nextflow ["processes"](https://www.nextflow.io/docs/edge/process.html)
- `nextflow.config`: [Nextflow configuration](https://www.nextflow.io/docs/edge/config.html) for different execution environments (YCRC/AWS Batch) and levels of geography (counties/states)

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
