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
        file 'mapping.csv'

    publishDir "$params.webdir/$params.date", enabled: params.s3pub
    publishDir "$params.webdir/stage",  enabled: params.s3pub, overwrite: true

    """
    # Create a WebPack file for serving to web browsers
    serialize.R -o summary.pack --pop /opt/webworker/data/fipspop.csv $allResults && \
      gzip summary.pack

    # Gzip the estimates
    cat $allResults > estimates.csv
    gzip -k estimates.csv

    if [ -z ${COVIDESTIM_ENDPOINT+x} ]; then
        insert.R \
          --summary  "$allResults" \
          --input    "$inputData" \
          --metadata "$metadata" \
          --key       fips \
          --run-date  $params.date \
          --save-mapping mapping.csv
    else
        echo "COVIDESTIM_ENDPOINT not specified; skipping DB inserts";
    fi
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
        file 'mapping.csv'

    publishDir "$params.webdir/$params.date/state", enabled: params.s3pub
    publishDir "$params.webdir/stage/state", enabled: params.s3pub, overwrite: true

    """
    RtLiveConvert.R \
      -o summary.pack \
      --pop /opt/webworker/data/statepop.csv \
      --input $inputData \
      --method $method \
      $allResults && \
      gzip summary.pack

    cat $allResults > estimates.csv
    gzip -k estimates.csv

    if [ -z ${COVIDESTIM_ENDPOINT+x} ]; then
        insert.R \
          --summary  "$allResults" \
          --input    "$inputData" \
          --method   "$method" \
          --metadata "$metadata" \
          --key       state \
          --run-date  $params.date \
          --save-mapping mapping.csv
    else
        echo "COVIDESTIM_ENDPOINT not specified; skipping DB inserts";
    fi
    """
}

