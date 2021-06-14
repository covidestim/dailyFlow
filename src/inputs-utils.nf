// Receive input data, either for states or counties, and split it by the
// geographic tract under consideration ("fips" or "state"). The resulting
// `.csv`s are delivered to the `runTract` process.
process filterTestTracts {

    container 'covidestim/webworker:latest'
    time '10m'

    input:
      file allTractData
      file rejects
    output:
      path 'filtered_data.csv', emit: data
      path 'rejects.csv', emit: rejects

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
    memory '4GB' // Unknown what it actually needs, but this is a good starting point

    input:
      file allTractData
      file rejects
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

