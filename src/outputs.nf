process publishCountyResults {

    container 'covidestim/webworker:latest'
    time '1h'
    memory '4GB'

    secret 'COVIDESTIM_JWT'

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
        file 'mapping.csv'

    publishDir "$params.webdir/$params.date", enabled: params.s3pub
    publishDir "$params.webdir/stage",  enabled: params.s3pub, overwrite: true

    """
    # Create a WebPack file for serving to web browsers
    covidestim-serialize-counties \
      -o summary.pack \
      --pop /opt/webworker/data/fipspop.csv \
      $allResults && \
    gzip -f summary.pack

    # Gzip the estimates
    cp $allResults estimates.csv && gzip -kf estimates.csv

    covidestim-insert \
      --summary  "$allResults" \
      --input    "$inputData" \
      --metadata "$metadata" \
      --key       fips \
      --run-date  $params.date \
      --save-mapping mapping.csv
    """
}

process publishStateResults {

    container 'covidestim/webworker:latest'
    time '1h'
    memory '4GB'

    secret 'COVIDESTIM_JWT'

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
        file 'mapping.csv'

    publishDir "$params.webdir/$params.date/state", enabled: params.s3pub
    publishDir "$params.webdir/stage/state", enabled: params.s3pub, overwrite: true

    """
    covidestim-serialize-states \
      -o summary.pack \
      --pop /opt/webworker/data/statepop.csv \
      --input $inputData \
      --method $method \
      $allResults && \
      gzip -f summary.pack

    cp $allResults estimates.csv && gzip -kf estimates.csv

    covidestim-insert \
      --summary  "$allResults" \
      --input    "$inputData" \
      --method   "$method" \
      --metadata "$metadata" \
      --key       state \
      --run-date  $params.date \
      --save-mapping mapping.csv
    """
}

