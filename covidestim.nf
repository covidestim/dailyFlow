#!/usr/bin/env nextflow

params.key = "state"

process makeTractData {

    output:
        file 'data.csv' into allTractData

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    """
    git clone https://github.com/covidestim/covidestim-sources && \
    cd covidestim-sources && \
    git submodule init && \
    git submodule update && \
    make -B data-products/covidtracking-smoothed.csv && \
    mv data-products/covidtracking-smoothed.csv ../data.csv
    """
}

// Receive input data, either for states or counties, and split it by the 
// type of geographic tract under consideration. Send each resulting `.csv`
// onto a channel, to be sent to the `runTract` process.
process splitTractData {

    // This defines which container to use for BOTH Singularity and Docker
    container 'rocker/tidyverse'

    input:
        file x from allTractData
    output:
        // 'mode flatten' means that each `.csv` file is sent as its own item
        // onto the channel. This feature is deprecated.
        file '*.csv' into tractData mode flatten

    """
    #!/usr/local/bin/Rscript
    library(tidyverse)

    d <- read_csv("$x") %>% group_by($params.key) %>%
      group_walk(~write_csv(.x, paste0(.y, ".csv")))
    """
}

process runTract {

    container 'covidestim/covidestim'
    time '4.5h'
    cpus 3

    // Retry once, before giving up
    errorStrategy 'retry'
    maxRetries 1

    tag "$f"

    input:
        file f from tractData
    output:
        tuple val(${f.getSimpleName}), \
              file('summary.csv'), \
              file('warnings.csv') into results

    shell:
    '''
    #!/usr/local/bin/Rscript
    library(tidyverse)
    library(covidestim)

    runner <- purrr::quietly(covidestim::run)

    d <- read_csv("!{f}")

    d_cases   <- transmute(d, date, observation = cases)
    d_deaths  <- transmute(d, date, observation = deaths)
    d_fracpos <- transmute(d, date, observation = fracpos)

    cfg <- covidestim(ndays = nrow(d),
                      seed  = sample.int(.Machine$integer.max, 1)) +
      input_cases(d_cases) +
      input_deaths(d_deaths) +
      input_fracpos(d_fracpos)
    
    result <- runner(cfg, cores = 3)

    run_summary <- summary(result$result)
    warnings    <- result$warnings

    write_csv(tibble(warnings=result$warnings), 'warnings.csv')
    write_csv(run_summary, 'summary.csv')
    '''
}

result.view()
