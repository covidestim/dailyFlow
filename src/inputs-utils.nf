// Receive input data, either for states or counties, and split it by the
// geographic tract under consideration ("fips" or "state"). The resulting
// `.csv`s are delivered to the `runTract` process.
process filterTestTracts {

    container 'covidestim/webworker:metadata'
    time '10m'

    input:
      file allTractData
      file rejects
      file metadata
    output:
      path 'filtered_data.csv', emit: data
      path 'rejects.csv', emit: rejects
      path 'produced_metadata.json', emit: metadata

    """
    filterTestTracts.R \
      -o filtered_data.csv \
      --writeMetadata produced_metadata.json \
      --metadata $metadata \
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
      file metadata
    output:
      file '*.csv', emit: timeseries
      file '*.json', emit: metadata

    shell:
    """
    #!/usr/local/bin/Rscript
    library(tidyverse)

    d <- read_csv("!{allTractData}")

    metadata <- jsonlite::read_json("!{metadata}", simplifyVector = T)

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

    group_by(metadata, flight = tractsGrouped[!{params.key}]) %>%
      group_walk(
        ~jsonlite::write_json(
          .x,
          ifelse(
            # If there is only one tract in this group
            (!{params.ngroups} == 10000000) ||
            (pull(.x, !{params.key}) %>% unique %>% length) == 1,
            # Then name the JSON file after that tract
            paste0(.x[["!{params.key}"]][1], ".json"),
            # Otherwise, name it after the number (index) of the group
            paste0(.y[["flight"]], ".json")
          ),
          null = 'null'
        )
      )
    """
}

