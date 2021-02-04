#!/usr/bin/env nextflow

// Enable DSL2
nextflow.enable.dsl = 2

params.PGCONN       = "null"   // By default, there's no DB connection
params.timemachine  = false    // By default, use latest data
params.alwayssample = false    // By default, fall back to the optimizer for states
params.n            = -1       // By default, run all tracts
params.ngroups      = 10000000 // By default, each tract gets its own NF process
params.branch       = "master" // Branch of model to run - must be on Docker Hub
params.key          = "fips"   // "fips" for county runs, "state" for state runs
params.raw          = false    // Output raw `covidestim-result` object as .RDS?
params.time         = ["70m", "2h", "150m"] // Time for running each tract
params.s3pub        = false    // Don't upload to S3 by default

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

    output: path 'data.csv', emit: data

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
    time '15m'

    output: path 'data.csv', emit: data

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    shell:

    if (params.timemachine != false)
      """
      echo "Using time machine ending on date !{params.timemachine}"
      git clone https://github.com/covidestim/covidestim-sources && \
        cd covidestim-sources && \
        git submodule init && \
        git submodule update --remote data-sources/jhu-data && \
        cd data-sources/jhu-data && \
        git log -1 --before !{params.timemachine}T06:00:00Z --pretty=%h | xargs git checkout && \
        cd ../.. && \
        make -B data-products/jhu-counties.csv && \
        mv data-products/jhu-counties.csv ../data.csv
      """
    else 
      """
      echo "Not using time machine; pulling latest data"
      git clone https://github.com/covidestim/covidestim-sources && \
        cd covidestim-sources && \
        git submodule init && \
        git submodule update --depth 1 --remote data-sources/jhu-data && \
        make -B data-products/jhu-counties.csv && \
        mv data-products/jhu-counties.csv ../data.csv
      """
}

// Receive input data, either for states or counties, and split it by the
// geographic tract under consideration ("fips" or "state"). The resulting
// `.csv`s are delivered to the `runTract` process.
process filterTestTracts {

    container 'covidestim/webworker:latest'
    time '10m'

    input:  file allTractData
    output: path 'filtered_data.csv', emit: data

    """
    filterTestTracts.R \
      -o filtered_data.csv \
      --tracts /opt/webworker/data/test-tracts.csv \
      --key $params.key \
      $allTractData
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

    shell:
    """
    #!/usr/local/bin/Rscript
    library(tidyverse)

    d <- read_csv("!{allTractData}")

    tractsUnique <- pull(d, !{params.key}) %>% unique

    tractsGrouped        <- 1:length(tractsUnique) %% !{params.ngroups}
    names(tractsGrouped) <- tractsUnique

    group_by(d, flight = tractsGrouped[!{params.key}]) %>%
      arrange(!{params.key}, date) %>%
      group_walk(
        ~write_csv(
          .x,
          ifelse(
            # If there is only one tract in this group
            (!{params.ngroups} == 10000000) ||
            (pull(.x, !{params.key}) %>% unique %>% length) == 1,
            # Then name the CSV file after that tract
            paste0(.x[["!{params.key}"]][1], ".csv"),
            # Otherwise, name it after the number (index) of the group
            paste0(.y[["flight"]], ".csv")
          )
        )
      )
    """
}

process runTractSampler {

    container "covidestim/covidestim:$params.branch" // Specify as --branch
    cpus 3
    memory '1.5 GB' // Usually needs ~800MB

    // Retry with stepped timelimits
    time          { params.time[task.attempt - 1] }
    errorStrategy { task.attempt == params.time.size() ? 'ignore' : 'retry' }
    maxRetries    { params.time.size() }

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
        path 'optvals.csv', emit: optvals
        path 'method.csv',  emit: method
        path "${task.tag}.RDS" optional !params.raw

    shell:
    '''
    #!/usr/local/bin/Rscript
    library(tidyverse); library(covidestim)

    runner          <- purrr::quietly(covidestim::run)
    runnerOptimizer <- purrr::quietly(covidestim::runOptimizer)

    d <- read_csv(
      "!{tractData}",
      col_types = cols(
        .default = col_guess(),
        !{params.key} = col_character()
      )
    ) %>% group_by(!{params.key})

    print("Tracts in this process:")
    print(pull(d, !{params.key}) %>% unique)

    allResults <- group_map(d, function(tractData, groupKeys) {

      region <- groupKeys[["!{params.key}"]]

      d_cases  <- select(tractData, date, observation = cases)
      d_deaths <- select(tractData, date, observation = deaths)

      cfg <- covidestim(ndays    = nrow(tractData),
                        seed     = sample.int(.Machine$integer.max, 1),
                        region   = region,
                        pop_size = get_pop(region)) +
        input_cases(d_cases) + input_deaths(d_deaths)

      print(cfg)
      resultOptimizer <- runnerOptimizer(cfg, cores = 1, tries = 10)
   
      run_summary <- summary(resultOptimizer$result)
      warnings    <- resultOptimizer$warnings
      opt_vals    <- resultOptimizer$result$opt_vals

      # If it's the last attempt
      if ("!{task.attempt == params.time.size()}" == "true" &&
          "!{params.alwayssample}" == "false") {
        return(list(
          run_summary = bind_cols(!{params.key} = region, run_summary),
          warnings    = bind_cols(!{params.key} = region, warnings = warnings),
          opt_vals    = bind_cols(!{params.key} = region, optvals  = opt_vals),
          method      = bind_cols(!{params.key} = region, method   = "optimizer"),
          raw         = resultOptimizer
        ))
      }

      result <- runner(cfg, cores = !{task.cpus})
 
      run_summary <- summary(result$result)
      warnings    <- result$warnings

      # Error on treedepth warning, or any divergent transitions warning
      # indicating >= 10 divergent transitions
      if (any(str_detect(warnings, 'treedepth')) ||
          any(str_detect(warnings, ' [0-9]{2,} divergent')))
        quit(status=1)

      return(list(
        run_summary = bind_cols(!{params.key} = region, run_summary),
        warnings    = bind_cols(!{params.key} = region, warnings = warnings),
        opt_vals    = tibble(!{params.key} = region,    optvals = numeric()),
        method      = bind_cols(!{params.key} = region, method = "sampler"),
        raw         = result
      ))
    })

    write_csv(purrr::map(allResults, 'run_summary') %>% bind_rows, 'summary.csv')
    write_csv(purrr::map(allResults, 'warnings')    %>% bind_rows, 'warning.csv')
    write_csv(purrr::map(allResults, 'opt_vals')    %>% bind_rows, 'optvals.csv')
    write_csv(purrr::map(allResults, 'method')      %>% bind_rows, 'method.csv')

    if ("!{params.raw}" == "true")
      saveRDS(purrr::map(allResults, 'raw'), "!{task.tag}.RDS")
    '''
}

process runTractOptimizer {

    container "covidestim/covidestim:$params.branch" // Specify as --branch
    cpus 1
    memory '1.5 GB' // Usually needs ~800MB

    time '1h'

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
        path 'optvals.csv', emit: optvals
        path "${task.tag}.RDS" optional !params.raw

    shell:
    '''
    #!/usr/local/bin/Rscript
    library(tidyverse); library(covidestim)

    runner <- purrr::quietly(covidestim::runOptimizer)

    d <- read_csv(
      "!{tractData}",
      col_types = cols(.default = col_guess(), !{params.key} = col_character())
    ) %>%
      group_by(!{params.key})

    print("Tracts in this process:")
    print(pull(d, !{params.key}) %>% unique)

    allResults <- group_map(d, function(tractData, groupKeys) {

      region <- groupKeys[["!{params.key}"]]

      d_cases  <- select(tractData, date, observation = cases)
      d_deaths <- select(tractData, date, observation = deaths)

      cfg <- covidestim(ndays    = nrow(tractData),
                        seed     = sample.int(.Machine$integer.max, 1),
                        region   = region,
                        pop_size = get_pop(region)) +
        input_cases(d_cases) + input_deaths(d_deaths)

      print(cfg)
      result <- runner(cfg, cores = 1, tries = 10)
   
      run_summary <- summary(result$result)
      warnings    <- result$warnings

      list(
        run_summary = bind_cols(!{params.key} = region, run_summary),
        warnings    = bind_cols(!{params.key} = region, warnings = warnings),
        opt_vals    = bind_cols(!{params.key} = region, optvals = result$result$opt_vals),
        raw         = result
      )
    })

    write_csv(purrr::map(allResults, 'run_summary') %>% bind_rows, 'summary.csv')
    write_csv(purrr::map(allResults, 'warnings')    %>% bind_rows, 'warning.csv')
    write_csv(purrr::map(allResults, 'opt_vals')    %>% bind_rows, 'optvals.csv')

    if ("!{params.raw}" == "true")
      saveRDS(purrr::map(allResults, 'raw'), "!{task.tag}.RDS")
    '''
}

process publishCountyResults {

    container 'covidestim/webworker:latest'
    time '30m'

    input:
        file allResults
        file inputData
        file allWarnings
        file optVals
    output:
        file 'summary.pack.gz'
        file 'estimates.csv'
        file 'estimates.csv.gz'

    publishDir "$params.webdir/$params.date", enabled: params.s3pub
    publishDir "$params.webdir/stage",  enabled: params.s3pub, overwrite: true

    """
    # Create a WebPack file for serving to web browsers
    serialize.R -o summary.pack --pop /opt/webworker/data/fipspop.csv $allResults && \
      gzip summary.pack

    # Gzip the estimates
    cat $allResults > estimates.csv
    gzip -k estimates.csv

    if [ "$params.PGCONN" != "null" ]; then
      # Add a run.date column and insert the results into the database.
      # `tagColumn` is an awk script from the `webworker` container.
      tagColumnAfter 'run.date' "$params.date" < $allResults | \
        psql -f /opt/webworker/scripts/copy_county_estimates_dev.sql "$params.PGCONN"

      # Do the same for warnings, but prepend the 'run.date' column because of a
      # preexisting poor choice of SQL table structure..
      tagColumnBefore 'run.date' "$params.date" < $allWarnings | \
        psql -f /opt/webworker/scripts/copy_warnings_dev.sql "$params.PGCONN"

      # And finally, copy the input data
      tagColumnAfter 'run.date' "$params.date" < $inputData | \
        psql -f /opt/webworker/scripts/copy_inputs_dev.sql "$params.PGCONN"
    else
      echo "PGCONN not supplied, DB inserts skipped."
    fi
    """
}

process publishStateResults {

    container 'covidestim/webworker:latest'
    time '30m'

    input:
        file allResults
        file inputData
        file warning
        file optVals
    output:
        file 'summary.pack.gz'
        file 'estimates.csv'
        file 'estimates.csv.gz'

    publishDir "$params.webdir/$params.date/state", enabled: params.s3pub
    publishDir "$params.webdir/stage/state", enabled: params.s3pub, overwrite: true

    """
    RtLiveConvert.R \
      -o summary.pack \
      --pop /opt/webworker/data/statepop.csv \
      --input $inputData \
      $allResults && \
      gzip summary.pack

    cat $allResults > estimates.csv
    gzip -k estimates.csv
    """
}

def collectCSVs(chan, fname) {
    chan.collectFile(
        name: fname,
        storeDir: params.outdir,
        keepHeader: true,
        skip: 1
    )
}

generateData = params.key == "fips" ? jhuData : ctpData
runTract = params.key == "fips" ? runTractOptimizer : runTractSampler

workflow {
main:
    generateData | filterTestTracts | splitTractData | flatten | take(params.n) | runTract

    if (params.key == "fips") {
        summary = collectCSVs(runTractOptimizer.out.summary, 'summary.csv')
        warning = collectCSVs(runTractOptimizer.out.warning, 'warning.csv')
        optvals = collectCSVs(runTractOptimizer.out.optvals, 'optvals.csv')
    } else {
        summary = collectCSVs(runTractSampler.out.summary, 'summary.csv')
        warning = collectCSVs(runTractSampler.out.warning, 'warning.csv')
        optvals = collectCSVs(runTractSampler.out.optvals, 'optvals.csv')
        method  = collectCSVs(runTractSampler.out.method,  'method.csv' )
    }

    if (params.key == "fips")
        publishCountyResults(summary, jhuData.out.data, warning, optvals)
    else
        publishStateResults(summary, ctpData.out.data, warning, optvals)

emit:
    summary = summary
    warning = warning
    optvals = optvals
}
