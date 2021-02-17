process publishCountyResults {

    container 'covidestim/webworker:latest'
    time '30m'

    input:
        file allResults
        file inputData
        file allWarnings
        file optVals
    output:
        file 'summary.pack.gz'
        file 'estimates.csv'
        file 'estimates.csv.gz'

    publishDir "$params.webdir/$params.date", enabled: params.s3pub
    publishDir "$params.webdir/stage",  enabled: params.s3pub, overwrite: true

    """
    # Create a WebPack file for serving to web browsers
    serialize.R -o summary.pack --pop /opt/webworker/data/fipspop.csv $allResults && \
      gzip summary.pack

    # Gzip the estimates
    cat $allResults > estimates.csv
    gzip -k estimates.csv

    if [ "$params.PGCONN" != "null" ]; then
      # Add a run.date column and insert the results into the database.
      # `tagColumn` is an awk script from the `webworker` container.
      tagColumnAfter 'run.date' "$params.date" < $allResults | \
        psql -f /opt/webworker/scripts/copy_county_estimates_dev.sql "$params.PGCONN"

      # Do the same for warnings, but prepend the 'run.date' column because of a
      # preexisting poor choice of SQL table structure..
      tagColumnBefore 'run.date' "$params.date" < $allWarnings | \
        psql -f /opt/webworker/scripts/copy_warnings_dev.sql "$params.PGCONN"

      # And finally, copy the input data
      tagColumnAfter 'run.date' "$params.date" < $inputData | \
        psql -f /opt/webworker/scripts/copy_inputs_dev.sql "$params.PGCONN"
    else
      echo "PGCONN not supplied, DB inserts skipped."
    fi
    """
}

process publishStateResults {

    container 'covidestim/webworker:latest'
    time '30m'

    input:
        file allResults
        file inputData
        file warning
        file optVals
        file method
    output:
        file 'summary.pack.gz'
        file 'estimates.csv'
        file 'estimates.csv.gz'

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
    """
}

