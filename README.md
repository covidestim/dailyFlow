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

Broadly speaking, a typical workflow execution produces state or county estimates, and optionally makes them publicly available.

### States

![State workflow](/images/states.drawio.png)

Notes:

- Broadcast and aggregation steps are generally handled through the use of Nextflow channel operators - see [`main.nf`](main.nf).
- CLI options and [profiles](https://www.nextflow.io/docs/edge/config.html?highlight=profile#config-profiles) control various behaviors of each process.

### Counties

![County workflow](/images/counties.drawio.png)

Notes:

- CLI options and [profiles](https://www.nextflow.io/docs/edge/config.html?highlight=profile#config-profiles) control various behaviors of each process.

## Getting started

Install Nextflow at [nextflow.io](https://www.nextflow.io/). You need at least `21.09.0-edge` because we use the Secrets feature. Nextflow will take care of downloading all containers from [Docker Hub](https://hub.docker.com/u/covidestim) the first time you run this pipeline. Next, take note of the following configuration options. You'll want to use different configuration options depending on whether you're developing locally, testing on the cluster, or deploying production code.

### Database configuration

There are four different configurations of the API:

- [No API](#no-api)
- [Local API](#local-api) + optional [dbstan integration](#enabling-dbstan-integration)
- [Test API](#test-api) + optional [dbstan integration](#enabling-dbstan-integration)
- [Production API](#production-api) + optional [dbstan integration](#enabling-dbstan-integration)

Most configurations require setting [Nextflow Secrets](https://www.nextflow.io/docs/edge/secrets.html). Be sure to read the Secrets documentation before proceeding.

#### No API

This runs the pipeline without persisting any data to a database, useful for model testing.

| option         | value   |
| -------------- | ------- |
| `--insertApi`  | `false` |

#### Local API

You can easily spin up a local database and API by cloning [covidestim/db](https://github.com/covidestim/db) and running `docker-compose up` from the root of that repository. This will give you a database and API that matches our production schema.

You must generate a JWT for your local API server so that you can define the mandatory Nextflow Secret `COVIDESTIM_JWT`. Follow steps 2 and 3 of [this PostgREST tutorial](https://postgrest.org/en/stable/tutorials/tut1.html#step-2-make-a-secret).

| option         | value   |
| -------------- | ------- |
| `-profile`     | `api_local` |
| Nextflow Secret `COVIDESTIM_JWT` | defined |

#### Test API

We run a test API server at https://api2-test.covidestim.org. Its schema is the same as the production database, but there is less model data stored in it. You'll need to generate or be provided a JWT token to insert runs via this API.

| option         | value   |
| -------------- | ------- |
| `-profile`     | `api_local` |
| Nextflow Secret `COVIDESTIM_JWT` | defined |

#### Production API

This is https://api2.covidestim.org. JWT token must be generated or provided.

| option         | value   |
| -------------- | ------- |
| `-profile`     | `api_local` |
| Nextflow Secret `COVIDESTIM_JWT` | defined |

#### Enabling [dbstan](https://github.com/covidestim/dbstan) integration

Keep in mind that `dbstan` inserts take up a lot of space in the database, and we don't yet automatically delete old dbstan runs. Enabling the dbstan integration is not necessary to run the pipeline for test or production.

| option         | value   |
| -------------- | ------- |
| `-profile`     | `dbstan_enable` |
| Nextflow Secret `COVIDESTIM_DBSTAN_HOST` | defined, must be hostname of a Postgres server that is listening on port 5432 |
| Nextflow Secret `COVIDESTIM_DBSTAN_DBNAME` | defined, Postgres db name |
| Nextflow Secret `COVIDESTIM_DBSTAN_USER` | defined, Postgres user, see [here](https://github.com/covidestim/dbstan/blob/master/init/init.sql) (`dbstan_writer`) |
| Nextflow Secret `COVIDESTIM_DBSTAN_PASS` | defined, Postgres user password |

### Runtime options

There are parameters defined in `main.nf` which can be configured at runtime in the CLI (`nextflow run --arg1 val1 --arg2 val2 ...`). The available CLI options are:

#### Required Flags

- `-profile`
  - Specify `states` or `counties`
  - Specify `local` or `slurm`
  - See [Configuration](#database-configuration) section above for API/dbstan-specific profiles.
- `--branch <tag>`: Use the Docker Hub container with tag = `<tag>` when running the model. Note that the GitHub branch `master` will exist as the Docker Hub container with tag = `latest`.
- `--key <state|fips>`
- `--date YYYY-MM-DD`: Sets the nominal "run date" for the run. Does not necessarily need to be the same as today's date. For example, if you are generating historical results, you would set `--date` to a date other than today's date.
  
#### Optional Flags

- `--inputUrl <url>`: This bypasses the usual data-cleaning process, and instead passes premade input data to the instances of the model. `<url>` point to a `.tar.gz` file containing `data.csv`, `metadata.json`, and `rejects.csv`. These files must have the same schema that would be produced by the normal data-cleaning process, but need not contain all geographies. *Hint:* An easy way to create these three files is to take the output of [`jhuStateVaxData`](src/inputs.nf) or [`combinedVaxData`](src/inputs.nf) and modify it to suit your needs, then run `tar -czf custom-inputs.tar.gz data.csv metadata.json rejects.csv`.
- `--ngroups`: When you have more geographies to model than you have hourly submissions to the SLURM scheduler, set this to cause geographies to be batched together into processes that contain multiple geographies.
- `--raw`: This will save all [`covidestim-result`](https://github.com/covidestim/covidestim/blob/85eae539efa482ff2aae515f3fa84b8886a861b1/R/covidestim.R#L483) objects to `.RDS` files, using the name of each geography as the filename, or the group id, if `--ngroups` is used. This can take up a lot of space. These objects are archival objects created by the Covidestim R package.
- `--splicedate`: *Deprecated*.
- `--testtracts`: *Deprecated*.
- `--alwaysoptimize`: Always use BFGS
- `--alwayssample`: Always sample, never fallback to BFGS
- `--n <number>`: Run the first `n` counties or states (in no particular order). Useful for testing.
- `--s3pub`: Publish results to AWS S3. The AWS CLI must be available on the Nextflow host system, and must be configued with necessary permissions to copy files to the destination bucket.
- `-stub`: Use the stub methods for input data generation. This will use premade data from [`covidestim-sources/example-output`](https://github.com/covidestim/covidestim-sources/tree/master/example-output), and is much faster than invoking `make` to create all input data from scratch. Useful for testing.

### Examples

**County production run, local**

Run the county pipeline locally, inserting the results into the database, and
uploading static files to S3. Available in repository as
[`scripts/runLocal-counties-prod.sh`](scripts/runLocal-counties-prod.sh).

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

**State test run, local**

Run the state pipeline locally with a custom branch, without publishing or inserting results.

```bash
#!/usr/bin/env bash
export NXF_ENABLE_SECRETS=true

# NOTE: Execute this from the repository root.

branch="my-custom-branch-tag"
key=state
date=$(date +%Y-%m-%d)

nextflow run . \
  --key $key -profile "states,local" \
  --branch $branch \
  --outdir test-state-$date \
  --date $date 
```

## FAQ

**How do I change the number of attempts that will be made to successfully run a model, as well as the length of each attempt?**

Change [`nextflow.config`](nextflow.config) by modifying the `states` and `counties` profiles.

**How do I change how Stan is invoked?**

See [covidestim-batch](https://github.com/covidestim/covidestim/blob/master/exec/batch.R) for available CLI options. To change functionality that is not modifiable via this CLI, modify `covidestim-batch` yourself, and rebuild a local `webworker` container so that Nextflow excecutes your modified script.

**How do I pass made-up case/death data to the model?**

Use the `--inputUrl` CLI flag (see [Optional Flags](#optional-flags)). Alternatively, use the model outside the Nextflow workflow, which may be easier in some circumstances, like testing new kinds of input data.

**How do I run the workflow using an updated or different version of the model? Or a new version of the `webworker` container**

For running a custom model version, invoke the `--branch` flag when issuing the `nextflow run` command in the terminal. `<branch>` must be the name of a tag which exists on [Docker Hub](https://hub.docker.com/r/covidestim/covidestim). If there doesn't exist a container (tag) for that branch or tag, you'll need to push a new branch or tag to the GitHub remote at `covidestim/covidestim`, and then set up a rule in Docker Hub so that it auto-builds that branch or tag. You need special privileges to set these rules. You can also build a container locally, and push it to Docker Hub using `docker push`.

For running a custom webworker container that doesn't have the `latest` tag on GitHub, you'll need to modify the `container` directives in all process definitions that list `covidestim/webworker:latest` as their container. To find which processes do this, run `find main.nf src/ -type f | xargs grep --color container` from the repository root.

*Important*: For running a *new* model that is now the `HEAD` of the branch currently being used, you need to ensure that three things have happened:

1. The new commit successfully pushed to `covidestim/covidestim`.
2. It was successfully built and tagged on Docker Hub (either autobuilt, or pushed to Docker Hub).
3. The local registry has the container. Locally, run `docker pull covidestim/covidestim:TAG`, and on the cluster, run `rm -rf work/singularity`, forcing Singularity to rebuild the Docker Hub-sourced container the next time Nextflow executes.

## File structure/Processes

The file structure is as follows:

- `main.nf`: The workflow
- `src/*.nf`: All of the Nextflow ["processes"](https://www.nextflow.io/docs/edge/process.html)
- `nextflow.config`: [Nextflow configuration](https://www.nextflow.io/docs/edge/config.html) for different execution environments (YCRC/AWS Batch) and levels of geography (counties/states)
- `scripts/`: Example bash scripts to run the workflow in different ways.

### `main.nf`

Specifies the main workflow and the default Nextflow parameters. The main workflow selects a process to generate model input data (counties = `jhuData`, states = `jhuStateData`), and connects the output of the selected process to the rest of the pipeline. The main workflow emits the following values:

- `summary`, a CSV of all model summaries
  
- `warning`, a CSV of all warnings from all model runs
  
- `optvals`, a CSV of the log-posteriors of all model runs performed using the BFGS algorithm
  
- `rejects`, a CSV of all counties or states which were rejected due to input data issues
  
`main.nf` references several processes which are defined in the `src/` directory: `jhuData`, `jhuStateData`, `runTractSampler`, `runTractOptimizer`, and auxillary processes `filterTestTracts`, `splitTractData`, `publishCountyResults`, `publishStateResults`.

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
