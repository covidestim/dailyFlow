#!/usr/bin/env nextflow

// Enable DSL2
nextflow.enable.dsl = 2

// By default, run all tracts
params.n = -1

params.branch = "master"

// The name of the grouping variable.
// "state": state-level runs
// "fips": county-level runs
params.key = "fips"

// Download `covidestim/covidestim-sources` and use its makefile to generate
// today's copy of either county-level or state-level data. Stage this data
// for splitting by `splitTractData`
process makeTractData {

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
    git submodule init && \
    git submodule update --remote data-sources/jhu-data && \
    make -B data-products/jhu-counties.csv && \
    mv data-products/jhu-counties.csv ../data.csv
    """
}

// Receive input data, either for states or counties, and split it by the 
// geographic tract under consideration. Send each resulting `.csv` onto a
// channel, to be delivered to the `runTract` process.
process splitTractData {

    // This defines which container to use for BOTH Singularity and Docker
    container 'rocker/tidyverse'
    time '1h'

    input:  file allInputData
    output: file '*.csv'

    """
    #!/usr/local/bin/Rscript
    library(tidyverse)

    d <- read_csv("$allInputData") %>%
      group_by($params.key) %>%
      arrange(date) %>%
      group_walk(~write_csv(.x, paste0(.y, ".csv")))
    """
}

process runTract {

    container "covidestim/covidestim:$params.branch"
    time '3h'
    cpus 3
    memory '1.5 GB'

    // Retry once, before giving up
    errorStrategy { task.attempt == 1 ? 'retry' : 'ignore' }
    maxRetries 1

    // Files from `tractData` are ALWAYS named by the tract they represent,
    // i.e. state name or FIPS code. We can get the name of the tract by
    // asking for the "simple name" of the file.
    tag "${f.getSimpleName()}"

    input:
        file f
    output:
        // output is [summary file for that run, warnings from rstan]
        path 'summary.csv', emit: summary
        path 'warning.csv', emit: warning

    shell:
    '''
    #!/usr/local/bin/Rscript
    library(tidyverse)
    library(covidestim)

    runner <- purrr::quietly(covidestim::run)

    d <- read_csv("!{f}")
    d_cases  <- select(d, date, observation = cases)
    d_deaths <- select(d, date, observation = deaths)

    cfg <- covidestim(ndays = nrow(d),
                      seed  = sample.int(.Machine$integer.max, 1)) +
      input_cases(d_cases) + input_deaths(d_deaths)
    
    result <- runner(cfg, cores = !{task.cpus}, open_progress = TRUE)
 
    run_summary <- summary(result$result)
    warnings    <- result$warnings

    write_csv(
      bind_cols(!{params.key} = "!{task.tag}", run_summary), 'summary.csv'
    )

    write_csv(
      tibble(!{params.key} = "!{task.tag}", warnings = warnings), 'warning.csv'
    )
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

workflow {
main:
    makeTractData | splitTractData | flatten | take(params.n) | runTract
emit:
    summary = collectCSVs(runTract.out.summary, 'summary.csv')
    warning = collectCSVs(runTract.out.warning, 'warning.csv')
}
