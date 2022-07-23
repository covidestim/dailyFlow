process publishCountyResults {

    container 'covidestim/webworker:latest'
    time '1h'
    memory '4GB'

    input:
        file allResults
        file inputData
        file rejects
        file allWarnings
        file optVals
        file metadata
    output:
        file 'summary.pack.gz'
        file 'estimates.csv'
        file 'estimates.csv.gz'

    publishDir "$params.webdir/$params.date", enabled: params.s3pub
    publishDir "$params.webdir/stage",  enabled: params.s3pub, overwrite: true

    script:
    """
    # Create a WebPack file for serving to web browsers
    covidestim-serialize-counties \
      -o summary.pack \
      --pop /opt/webworker/data/fipspop.csv \
      $allResults && \
    gzip -f summary.pack

    # Gzip the estimates
    cp $allResults estimates.csv && gzip -kf estimates.csv
    """
}

process publishStateResults {

    container 'covidestim/webworker:latest'
    time '1h'
    memory '4GB'

    input:
        file allResults
        file inputData
        file rejects
        file warning
        file optVals
        file method
        file metadata
    output:
        file 'summary.pack.gz'
        file 'estimates.csv'
        file 'estimates.csv.gz'

    publishDir "$params.webdir/$params.date/state", enabled: params.s3pub
    publishDir "$params.webdir/stage/state", enabled: params.s3pub, overwrite: true

    script:
    """
    covidestim-serialize-states \
      -o summary.pack \
      --pop /opt/webworker/data/statepop.csv \
      --input $inputData \
      --method $method \
      $allResults && \
      gzip -f summary.pack

    cp $allResults estimates.csv && gzip -kf estimates.csv
    """
}

process insertResults {

    container 'covidestim/webworker:latest'
    time '15m'
    memory '4GB'

    secret 'COVIDESTIM_JWT'

    input:
        file allResults
        file inputData
        file metadata
        file method
    output:
        file 'mapping.csv' optional !params.insertApi

    script:
    if (params.insertApi == true && params.key == "state")
        """
        covidestim-insert \
          --summary  "$allResults" \
          --input    "$inputData" \
          --metadata "$metadata" \
          --key       $params.key \
          --run-date  $params.date \
          --method   "$method" \
          --save-mapping mapping.csv
        """

    // No need for `--method`, these are all optimized
    else if (params.insertApi == true && params.key == "fips")
        """
        covidestim-insert \
          --summary  "$allResults" \
          --input    "$inputData" \
          --metadata "$metadata" \
          --key       $params.key \
          --run-date  $params.date \
          --save-mapping mapping.csv
        """
    
    else if (params.insertApi == true)
        error "params.key was not state/fips, value: ${params.key}"

    else if (params.insertApi == false)
        """
        echo 'params.insertApi == false, skipping DB inserts'
        """
    else
        error "params.insertApi was not true/false, value: ${params.insert}"
}

