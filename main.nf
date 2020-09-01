#!/usr/bin/env nextflow

// Enable DSL2
nextflow.enable.dsl = 2

params.n      = -1       // By default, run all tracts
params.branch = "master" // Branch of model to run - must be on Docker Hub
params.key    = "fips"   // "fips" for county runs, "state" for state runs
params.raw    = false    // Output raw `covidestim-result` object as .RDS?

// The first two processes generate either county- or state-level data.
// 
// Download repo `covidestim/covidestim-sources` and use its makefile to
// generate today's copy of either county-level or state-level data. Stage this
// data for splitting by `splitTractData`. This process uses state-level 
// Covid Tracking Project data. The next uses Johns Hopkins' county-level data.
process ctpData {
    container 'rocker/tidyverse'

    // Retry once in case of HTTP errors, before giving up
    errorStrategy 'retry'
    maxRetries 1
    time '5m'

    output: file 'data.csv'

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    """
    git clone https://github.com/covidestim/covidestim-sources && \
    cd covidestim-sources && \
    make -B data-products/covidtracking-smoothed.csv && \
    mv data-products/covidtracking-smoothed.csv ../data.csv
    """
}

process jhuData {
    container 'rocker/tidyverse' // Name of singularity+docker container

    // Retry once in case of HTTP errors, before giving up
    errorStrategy 'retry'
    maxRetries 1
    time '5m'

    output: file 'data.csv'

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    """
    git clone https://github.com/covidestim/covidestim-sources && \
    cd covidestim-sources && \
    git submodule init && \
    git submodule update --remote data-sources/jhu-data && \
    make -B data-products/jhu-counties.csv && \
    mv data-products/jhu-counties.csv ../data.csv
    """
}

// Receive input data, either for states or counties, and split it by the
// geographic tract under consideration ("fips" or "state"). The resulting
// `.csv`s are delivered to the `runTract` process.
process splitTractData {

    container 'rocker/tidyverse'
    time '1h' // S3 copies take forever, probably a better way to do this

    input:  file allTractData
    output: file '*.csv'

    """
    #!/usr/local/bin/Rscript
    library(tidyverse)

    d <- read_csv("$allTractData") %>% group_by($params.key) %>%
      arrange(date) %>%
      group_walk(~write_csv(.x, paste0(.y, ".csv")))
    """
}

process runTract {

    container "covidestim/covidestim:$params.branch" // Specify as --branch
    time '3h'
    cpus 3
    memory '1.5 GB' // Usually needs ~800MB

    // Retry once, before giving up
    errorStrategy { task.attempt == 1 ? 'retry' : 'ignore' }
    maxRetries 1

    // Files from `splitTractData` are ALWAYS named by the tract they
    // represent, i.e. state name or county FIPS. We can get the name of the
    // tract by asking for the "simple name" of the file.
    tag "${tractData.getSimpleName()}"

    // Place .RDS files in 'raw/' directory, but only if --raw flag is passed
    publishDir "$params.outdir/raw", pattern: "*.RDS", enabled: params.raw

    input:
        file tractData
    output:
        path 'summary.csv', emit: summary // DSL2 syntax
        path 'warning.csv', emit: warning
        path "${task.tag}.RDS" optional !params.raw

    shell:
    '''
    #!/usr/local/bin/Rscript
    library(tidyverse); library(covidestim)

    runner <- purrr::quietly(covidestim::run)

    d <- read_csv("!{tractData}")
    d_cases  <- select(d, date, observation = cases)
    d_deaths <- select(d, date, observation = deaths)

    cfg <- covidestim(ndays = nrow(d),
                      seed  = sample.int(.Machine$integer.max, 1)) +
      input_cases(d_cases) + input_deaths(d_deaths)
    
    result <- runner(cfg, cores = !{task.cpus})
 
    run_summary <- summary(result$result)
    warnings    <- result$warnings

    write_csv(bind_cols(!{params.key} = "!{task.tag}", run_summary),
              'summary.csv')

    write_csv(tibble(!{params.key} = "!{task.tag}", warnings = warnings),
              'warning.csv')

    if ("!{params.raw}" == "true") saveRDS(result, "!{task.tag}.RDS")
    '''
}

def collectCSVs(chan, fname) {
    chan.collectFile(
        name: fname,
        storeDir: params.outdir,
        keepHeader: true,
        skip: 1
    )
}

dataGenerator = params.key == "fips" ? jhuData : ctpData

workflow {
main:
    dataGenerator | splitTractData | flatten | take(params.n) | runTract

emit:
    summary = collectCSVs(runTract.out.summary, 'summary.csv')
    warning = collectCSVs(runTract.out.warning, 'warning.csv')
}
