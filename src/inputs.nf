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
    shell:

    if (params.timemachine != false)
      """
      echo "Error: Cannot use timemachine for combinedVaxData!"
      exit 1
      """
    else 
      """
      # WARNING!!!!!!
      #              REMEMBER TO REMOVE `GIT CHECKOUT` BEFORE MERGING TO MASTER
      # /WARNING!!!!!!
      echo "Not using time machine; pulling latest data"
      git clone https://github.com/covidestim/covidestim-sources && \
        cd covidestim-sources && \
        git checkout immunity && \
        git submodule init && \
        git submodule update --depth 1 --remote data-sources/jhu-data && \
        git submodule update --depth 1 --remote data-sources/nytimes-data && \
        git submodule update --depth 1 --remote data-sources/gtown-vax && \
        cd data-sources/gtown-vax && \
        git checkout db2f126b379098d190b73342ba9e33160ab6c7fe && \
        cd ../.. && \
        make -B data-products/case-death-rr-vax.csv \
          data-products/combined-counties-rejects.csv \
          data-products/case-death-rr-vax-metadata.json && \
        mv data-products/case-death-rr-vax.csv ../data.csv && \
        mv data-products/case-death-rr-vax-metadata.json ../metadata.json && \
        mv data-products/combined-counties-rejects.csv ../rejects.csv
      """

    stub:
    """
    echo "Running stub method"
    git clone --depth 1 https://github.com/covidestim/covidestim-sources && \
      cd covidestim-sources && \
      mv example-output/case-death-rr.csv ../data.csv && \
      mv example-output/case-death-rr-metadata.json ../metadata.json && \
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
    shell:

    if (params.timemachine != false)
      """
      echo "Error: Cannot use timemachine for jhuStateVaxData!"
      exit 1
      """
    else 
      '''
      echo "Not using time machine; pulling latest data"
      git clone https://github.com/covidestim/covidestim-sources && \
        cd covidestim-sources && \
        git submodule init && \
        git submodule update --depth 1 --remote data-sources/jhu-data && \
        git submodule update --depth 1 --remote data-sources/gtown-vax && \
        cd data-sources/gtown-vax && \
        git checkout db2f126b379098d190b73342ba9e33160ab6c7fe && \
        cd ../.. && \
        make -B data-products/case-death-rr-state.csv \
          data-products/jhu-states-rejects.csv \
          data-products/case-death-rr-state-metadata.json && \
        mv data-products/case-death-rr-state.csv ../data.csv && \
        mv data-products/jhu-states-rejects.csv ../rejects.csv && \
        mv data-products/case-death-rr-state-metadata.json ../metadata.json
      '''

    stub:
    """
    echo "Running stub method"
    git clone --depth 1 https://github.com/covidestim/covidestim-sources && \
      cd covidestim-sources && \
      mv example-output/case-death-rr-state.csv ../data.csv && \
      mv example-output/case-death-rr-state-metadata.json ../metadata.json && \
      mv example-output/jhu-states-rejects.csv ../rejects.csv
    """
}

