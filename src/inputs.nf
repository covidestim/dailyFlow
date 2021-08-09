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

    output:
      path 'data.csv',    emit: data
      path 'rejects.csv', emit: rejects

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    """
    git clone https://github.com/covidestim/covidestim-sources && \
    cd covidestim-sources && \
    make -B data-products/covidtracking-smoothed.csv && \
    mv data-products/covidtracking-smoothed.csv ../data.csv

    echo 'state,code,reason' > ../rejects.csv
    """
}

process jhuData {
    container 'rocker/tidyverse' // Name of singularity+docker container

    // Retry once in case of HTTP errors, before giving up
    errorStrategy 'retry'
    maxRetries 1
    time '15m'

    // Currently unsure of exact memory needs. At least 300MB, but may differ
    // substantially be cluster.
    memory '8 GB'

    output:
      path 'data.csv',    emit: data
      path 'rejects.csv', emit: rejects

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
        make -B data-products/jhu-counties.csv data-products/jhu-counties-rejects.csv && \
        mv data-products/jhu-counties.csv ../data.csv && \
        mv data-products/jhu-counties-rejects.csv ../rejects.csv
      """
    else 
      """
      echo "Not using time machine; pulling latest data"
      git clone https://github.com/covidestim/covidestim-sources && \
        cd covidestim-sources && \
        git submodule init && \
        git submodule update --depth 1 --remote data-sources/jhu-data && \
        make -B data-products/jhu-counties.csv data-products/jhu-counties-rejects.csv && \
        mv data-products/jhu-counties.csv ../data.csv && \
        mv data-products/jhu-counties-rejects.csv ../rejects.csv
      """
}

process jhuVaxData {
    container 'covidestim/webworker:latest' // Name of singularity+docker container

    // Retry once in case of HTTP errors, before giving up
    errorStrategy 'retry'
    maxRetries 1
    time '50m'

    // Currently unsure of exact memory needs. At least 300MB, but may differ
    // substantially by cluster (Harvard seems to need more?).
    memory '8 GB'

    output:
      path 'data.csv',    emit: data
      path 'rejects.csv', emit: rejects

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    shell:

    if (params.timemachine != false)
      """
      echo "Error: Cannot use timemachine for jhuVaxData!"
      exit 1
      """
    else 
      """
      echo "Not using time machine; pulling latest data"
      git clone https://github.com/covidestim/covidestim-sources && \
        cd covidestim-sources && \
        git submodule init && \
        git submodule update --depth 1 --remote data-sources/jhu-data && \
        make -B data-products/case-death-rr.csv data-products/jhu-counties-rejects.csv && \
        mv data-products/case-death-rr.csv ../data.csv && \
        mv data-products/jhu-counties-rejects.csv ../rejects.csv
      """
}

process jhuStateData {
    container 'rocker/tidyverse' // Name of singularity+docker container

    // Retry once in case of HTTP errors, before giving up
    errorStrategy 'retry'
    maxRetries 1
    time '15m'

    // Currently unsure of exact memory needs. At least 300MB, but may differ
    // substantially be cluster.
    memory '8 GB'

    output:
      path 'data.csv',    emit: data
      path 'rejects.csv', emit: rejects

    // Clone the 'covidestim-sources' repository, and use it to generate
    // the input data for the model
    shell:

    if (params.timemachine != false)
      '''
      INPUTPREFIX=jhu-states!{params.splicedate ? "-spliced-" + params.splicedate : ""}

      echo "Using time machine ending on date !{params.timemachine}"
      git clone https://github.com/covidestim/covidestim-sources && \
        cd covidestim-sources && \
        git submodule init && \
        git submodule update --remote data-sources/jhu-data && \
        cd data-sources/jhu-data && \
        git log -1 --before !{params.timemachine}T06:00:00Z --pretty=%h | xargs git checkout && \
        cd ../.. && \
        make -B data-products/$INPUTPREFIX.csv \
          data-products/$INPUTPREFIX-rejects.csv && \
        mv data-products/$INPUTPREFIX.csv ../data.csv && \
        mv data-products/$INPUTPREFIX-rejects.csv ../rejects.csv
      '''
    else 
      '''
      INPUTPREFIX=jhu-states!{params.splicedate ? "-spliced-" + params.splicedate : ""}

      echo "Not using time machine; pulling latest data"
      git clone https://github.com/covidestim/covidestim-sources && \
        cd covidestim-sources && \
        git submodule init && \
        git submodule update --depth 1 --remote data-sources/jhu-data && \
        make -B data-products/$INPUTPREFIX.csv \
          data-products/$INPUTPREFIX-rejects.csv && \
        mv data-products/$INPUTPREFIX.csv ../data.csv && \
        mv data-products/$INPUTPREFIX-rejects.csv ../rejects.csv
      '''
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
      path 'data.csv',    emit: data
      path 'rejects.csv', emit: rejects

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
        make -B data-products/case-death-rr-state.csv \
          data-products/jhu-states-rejects.csv && \
        mv data-products/case-death-rr-state.csv ../data.csv && \
        mv data-products/jhu-states-rejects.csv ../rejects.csv
      '''
}

