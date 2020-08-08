#!/usr/bin/env nextflow

// The name of the grouping variable.
// "state": state-level runs
// "fips": county-level runs
params.key = "state"

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
    make -B data-products/covidtracking-smoothed.csv && \
    mv data-products/covidtracking-smoothed.csv ../data.csv
    """
}

// Receive input data, either for states or counties, and split it by the 
// geographic tract under consideration. Send each resulting `.csv` onto a
// channel, to be delivered to the `runTract` process.
process splitTractData {

    // This defines which container to use for BOTH Singularity and Docker
    container 'rocker/tidyverse'
    time '3m'

    input: file x from allTractData

    // 'mode flatten' means that each `.csv` file is sent as its own item
    // onto the channel. NOTE: This feature is deprecated.
    output: file '*.csv' into tractData mode flatten

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
    memory '1.5 GB'

    // Retry once, before giving up
    errorStrategy { task.attempt == 1 ? 'retry' : 'ignore' }
    maxRetries 1

    // Files from `tractData` are ALWAYS named by the tract they represent,
    // i.e. state name or FIPS code. We can get the name of the tract by
    // asking for the "simple name" of the file.
    tag "${f.getSimpleName()}"

    input:
        file f from tractData
    output:
        // output is [tract name, summary file for that run, warnings from rstan]
        tuple val("${f.getSimpleName()}"), \
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
#   write_csv(tibble(warnings="lol"), 'warnings.csv')
#   write_csv(tibble(deaths=0), 'summary.csv')
    '''
}

process summarize {
    container 'rocker/tidyverse'
    time '10m'

    publishDir "$params.outdir"

    input:
        stdin results.reduce("id,summary,warnings"){
            a, b -> "${a}\n" + "${b[0]},${b[1]},${b[2]}\n"
        }
    output:
        file 'summary.RDS'

    script:
    """
    #!/usr/local/bin/Rscript
    library(tidyverse)

    d <- read_csv(file('stdin')) %>%
       mutate_at(c('summary', 'warnings'), ~map(., read_csv))

    saveRDS(d, 'summary.RDS')
    """
}

