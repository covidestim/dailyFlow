// Receive input data, either for states or counties, and split it by the
// geographic tract under consideration ("fips" or "state"). The resulting
// `.csv`s are delivered to the `runTract` process.
process makeSyntheticIntervals {

    container 'covidestim/webworker:latest'
    time '10m'

    input:
      file data
      file metadata
      file backup
    output:
      path 'synthetic_summary.csv', emit: summary
      path 'produced_metadata.json', emit: metadata
      path 'backup.RDS' optional true

    publishDir "$params.webdir/synthetic-backup", enabled: params.s3pub, pattern: 'newBackup.RDS', saveAs: { 'backup.RDS' }

    """
    makeSyntheticIntervals.R \
      -o synthetic_summary.csv \
      --statepop /opt/webworker/data/statepop.csv \
      --backup $backup \
      --writeBackup newBackup.RDS \
      --vars infections,r_t,infections_cumulative \
      --minSampled 10 \
      --metadata $metadata \
      --writeMetadata produced_metadata.json \
      $data
    """
}

