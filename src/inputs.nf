// The first two processes generate either county- or state-level data.
// 
// Download repo `covidestim/covidestim-sources` and use its makefile to
// generate today's copy of either county-level or state-level data. Stage this
// data for splitting by `splitTractData`. This process uses state-level 
// Covid Tracking Project data. The next uses Johns Hopkins' county-level data.
process staticManuscriptData {
    container 'rocker/tidyverse'

    // Retry once in case of HTTP errors, before giving up
    errorStrategy 'retry'
    maxRetries 1
    time '5m'

    output:
      path 'data.csv',    emit: data
      path 'rejects.csv', emit: rejects

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    """
    wget "https://covidestim.s3.amazonaws.com/manuscript-fall-2021-input.tar.gz" && \
      tar -xzvf manuscript-fall-2021-input.tar.gz && \
      mv county.csv data.csv &&
      mv county-rejects.csv rejects.csv
    """
}

process staticManuscriptStateData {
    container 'rocker/tidyverse'

    // Retry once in case of HTTP errors, before giving up
    errorStrategy 'retry'
    maxRetries 1
    time '5m'

    output:
      path 'data.csv',    emit: data
      path 'rejects.csv', emit: rejects

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    """
    wget "https://covidestim.s3.amazonaws.com/manuscript-fall-2021-input.tar.gz" && \
      tar -xzvf manuscript-fall-2021-input.tar.gz && \
      mv state.csv data.csv &&
      mv state-rejects.csv rejects.csv
    """
}

process staticManuscriptDCData {
    container 'rocker/tidyverse'

    // Retry once in case of HTTP errors, before giving up
    errorStrategy 'retry'
    maxRetries 1
    time '5m'

    output:
      path 'data.csv',    emit: data
      path 'rejects.csv', emit: rejects

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    """
    wget "https://covidestim.s3.amazonaws.com/manuscript-fall-2021-input-DC.tar.gz" && \
      tar -xzvf manuscript-fall-2021-input-DC.tar.gz && \
      mv state.csv data.csv &&
      mv state-rejects.csv rejects.csv
    """
}

