// These two processes generate either county- or state-level data.
// 
// Download repo `covidestim/covidestim-sources` and use its makefile to
// generate today's copy of either county-level or state-level data. Stage this
// data for splitting by `splitTractData`. 
process combinedVaxData {
    container 'covidestim/webworker:latest' // Name of singularity+docker container

    // Retry once in case of HTTP errors, before giving up
    errorStrategy 'retry'
    maxRetries 1
    time '50m'

    // Currently unsure of exact memory needs. At least 300MB, but may differ
    // substantially by cluster (Harvard seems to need more?).
    memory '8 GB'

    output:
      path 'data.csv',      emit: data
      path 'rejects.csv',   emit: rejects
      path 'metadata.json', emit: metadata

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    script:

    if (params.inputUrl == false)
      """
      git clone https://github.com/covidestim/covidestim-sources && \
        cd covidestim-sources && \
        git lfs checkout && \
        git submodule init && \
        git submodule update --recommend-shallow --depth 1 --remote && \
        make -B data-products/case-death-rr-boost-hosp.csv \
          data-products/jhu-counties-rejects.csv \
          data-products/case-death-rr-boost-hosp-metadata.json && \
        mv data-products/case-death-rr-boost-hosp.csv ../data.csv && \
        mv data-products/case-death-rr-boost-hosp-metadata.json ../metadata.json && \
        mv data-products/jhu-counties-rejects.csv ../rejects.csv
      """
    else
      """
      echo "Using inputs from url $params.inputUrl"
      echo "Expecting .tar.gz archive with files data.csv, metadata.json, rejects.csv"
      wget -O inputs.tar.gz "$params.inputUrl" && \
        mkdir custom-inputs && \
        tar -C custom-inputs -xzvf inputs.tar.gz && \
        mv custom-inputs/{data.csv,metadata.json,rejects.csv} .
      """

    stub:
    """
    echo "Running stub method"
    git clone https://github.com/covidestim/covidestim-sources && \
      cd covidestim-sources && \
      mv example-output/case-death-rr-boost-hosp.csv ../data.csv && \
      mv example-output/case-death-rr-boost-hosp-metadata.json ../metadata.json && \
      mv example-output/jhu-counties-rejects.csv ../rejects.csv
    """
}

process jhuStateVaxData {
    container 'covidestim/webworker:latest' // Name of singularity+docker container

    // Retry once in case of HTTP errors, before giving up
    errorStrategy 'retry'
    maxRetries 1
    time '50m'

    // Currently unsure of exact memory needs. At least 300MB, but may differ
    // substantially be cluster.
    memory '8 GB'

    output:
      path 'data.csv',      emit: data
      path 'rejects.csv',   emit: rejects
      path 'metadata.json', emit: metadata

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    script:

    if (params.inputUrl == false)
      '''
      git clone https://github.com/covidestim/covidestim-sources && \
        cd covidestim-sources && \
        git lfs checkout && \
        git submodule init && \
        git submodule update --recommend-shallow --depth 1 --remote && \
        make -B data-products/case-death-rr-boost-hosp-state.csv \
          data-products/jhu-states-rejects.csv \
          data-products/case-death-rr-boost-hosp-state-metadata.json && \
        mv data-products/case-death-rr-boost-hosp-state.csv ../data.csv && \
        mv data-products/jhu-states-rejects.csv ../rejects.csv && \
        mv data-products/case-death-rr-boost-hosp-state-metadata.json ../metadata.json
      '''
    else
      """
      echo "Using inputs from url $params.inputUrl"
      echo "Expecting .tar.gz archive with files data.csv, metadata.json, rejects.csv"
      wget -O inputs.tar.gz "$params.inputUrl" && \
        mkdir custom-inputs && \
        tar -C custom-inputs -xzvf inputs.tar.gz && \
        mv custom-inputs/{data.csv,metadata.json,rejects.csv} .
      """

    stub:
    """
    echo "Running stub method"
    git clone --depth 1 https://github.com/covidestim/covidestim-sources && \
      cd covidestim-sources && \
      mv example-output/case-death-rr-boost-hosp-state.csv ../data.csv && \
      mv example-output/case-death-rr-boost-hosp-state-metadata.json ../metadata.json && \
      mv example-output/jhu-states-rejects.csv ../rejects.csv
    """
}

