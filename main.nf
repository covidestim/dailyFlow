#!/usr/bin/env nextflow

// The name of the grouping variable.
// "state": state-level runs
// "fips": county-level runs
params.key = "fips"

// The directory in which to store the principal output, `summary.csv`
params.outdir = "results"

// Download `covidestim/covidestim-sources` and use its makefile to generate
// today's copy of either county-level or state-level data. Stage this data
// for splitting by `splitTractData`
process makeTractData {

    container 'rocker/tidyverse'

    // Retry once in case of HTTP errors, before giving up
    errorStrategy 'retry'
    maxRetries 1
    time '5m'

    output: file 'data.csv' into allTractData

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    """
    git clone https://github.com/covidestim/covidestim-sources && \
    cd covidestim-sources && \
    git submodule init && \
    git submodule update && \
    make -B data-products/nytimes-counties.csv && \
    mv data-products/nytimes-counties.csv ../data.csv
    """
}

// Receive input data, either for states or counties, and split it by the 
// geographic tract under consideration. Send each resulting `.csv` onto a
// channel, to be delivered to the `runTract` process.
process splitTractData {

    // This defines which container to use for BOTH Singularity and Docker
    container 'rocker/tidyverse'
    time '15m'

    input: file x from allTractData

    // 'mode flatten' means that each `.csv` file is sent as its own item
    // onto the channel. NOTE: This feature is deprecated.
    output: file '*.csv' into tractData mode flatten

    """
    #!/usr/local/bin/Rscript
    library(tidyverse)

    d <- read_csv("$x") %>% group_by($params.key) %>%
      arrange(date) %>%
      group_walk(~write_csv(.x, paste0(.y, ".csv")))
    """
}

process runTract {

    container 'covidestim/covidestim:countymodel'
    time '30m'
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
        file f from tractData.take(1000)
    output:
        // output is [summary file for that run, warnings from rstan]
        file('summary.csv') into summaries
        file('warnings.csv') into warnings

    shell:
    '''
    #!/usr/local/bin/Rscript
    library(tidyverse)
    library(covidestim)

    runner <- purrr::quietly(covidestim::run)

    d <- read_csv("!{f}")

    d_cases   <- select(d, date, observation = cases)
    d_deaths  <- select(d, date, observation = deaths)

    cfg <- covidestim(ndays = nrow(d),
                      seed  = sample.int(.Machine$integer.max, 1)) +
      input_cases(d_cases) +
      input_deaths(d_deaths)
    
    result <- runner(cfg, cores = !{task.cpus},
                     open_progress = TRUE)
 
    run_summary <- summary(result$result)
    warnings    <- result$warnings

    write_csv(
      bind_cols(!{params.key} = "!{task.tag}", run_summary),
      'summary.csv'
    )

    write_csv(
      tibble(!{params.key} = "!{task.tag}", warnings = warnings),
      'warnings.csv'
    )
    '''
}

summaries
    .collectFile(name: 'summary.csv',
                 storeDir: params.outdir,
                 keepHeader: true,
                 skip: 1)

warnings
    .collectFile(name: 'warnings.csv',
                 storeDir: params.outdir,
                 keepHeader: true,
                 skip: 1)

