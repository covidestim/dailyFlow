process runTractSampler {

    container "covidestim/covidestim:$params.branch" // Specify as --branch
    cpus 3
    memory '3 GB' // Currently unsure of exact memory needs. At least 800MB

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
    memory '3 GB' // Currently unsure of exact memory needs. At least 800MB

    time '2h'

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
        method      = bind_cols(!{params.key} = region, method = 'optimizer'),
        raw         = result
      )
    })

    write_csv(purrr::map(allResults, 'run_summary') %>% bind_rows, 'summary.csv')
    write_csv(purrr::map(allResults, 'warnings')    %>% bind_rows, 'warning.csv')
    write_csv(purrr::map(allResults, 'opt_vals')    %>% bind_rows, 'optvals.csv')
    write_csv(purrr::map(allResults, 'method')      %>% bind_rows, 'method.csv')

    if ("!{params.raw}" == "true")
      saveRDS(purrr::map(allResults, 'raw'), "!{task.tag}.RDS")
    '''
}

