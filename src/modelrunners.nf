process runTractSampler {

    container "covidestim/covidestim:$params.branch" // Specify as --branch
    cpus 3
    memory '3 GB' // Currently unsure of exact memory needs. At least 800MB

    secret 'COVIDESTIM_DBSTAN_USER'
    secret 'COVIDESTIM_DBSTAN_PASS'

    // Retry with stepped timelimits
    time          { params.time[task.attempt - 1] }
    errorStrategy { task.attempt == params.time.size() ? 'ignore' : 'retry' }
    maxRetries    { params.time.size() - 1 }

    // Files from `splitTractData` are ALWAYS named by the tract they
    // represent, i.e. state name or county FIPS. We can get the name of the
    // tract by asking for the "simple name" of the file.
    tag "${tractData.getSimpleName()}"

    // Place .RDS files in 'raw/' directory, but only if --raw flag is passed
    publishDir "$params.outdir/raw", pattern: "*.RDS", enabled: params.raw

    input:
        tuple val(runID), file(tractData), file(metadata)
    output:
        path 'summary.csv', emit: summary // DSL2 syntax
        path 'warning.csv', emit: warning
        path 'optvals.csv', emit: optvals
        path 'method.csv',  emit: method
        path 'produced_metadata.json', emit: metadata
        path "${task.tag}.RDS" optional !params.raw

    script:
    attempts      = params.time.size() - task.attempt + 1
    dbstan_insert = params.insert ? "--dbstan-insert" : ""
    save_raw      = params.raw ? "--save-raw"      : ""
    raw_location  = params.raw ? "${task.tag}.RDS" : ""
    """
    covidestim-batch \
      --input $tractData \
      --key $params.key \
      --metadata $metadata \
      --attempts $attempts \
      --cpus $task.cpus \
      --save-summary summary.csv \
      --save-warning warning.csv \
      --save-optvals optvals.csv \
      --save-method  method.csv \
      --save-metadata produced_metadata.json \
      $dbstan_insert \
      $save_raw $raw_location
    """
}

process runTractOptimizer {

    container "covidestim/covidestim:$params.branch" // Specify as --branch
    cpus 1
    memory '3 GB' // Currently unsure of exact memory needs. At least 800MB

    time {
        params.ngroups == 10000000 ?
            20.seconds :
            20.seconds * 3300 / (params.ngroups as int)
    }

    errorStrategy "ignore"
    // maxRetries 1

    // Files from `splitTractData` are ALWAYS named by the tract they
    // represent, i.e. state name or county FIPS. We can get the name of the
    // tract by asking for the "simple name" of the file.
    tag "${tractData.getSimpleName()}"

    // Place .RDS files in 'raw/' directory, but only if --raw flag is passed
    publishDir "$params.outdir/raw", pattern: "*.RDS", enabled: params.raw

    input:
        tuple val(runID), file(tractData), file(metadata)
    output:
        path 'summary.csv', emit: summary // DSL2 syntax
        path 'warning.csv', emit: warning
        path 'optvals.csv', emit: optvals
        path 'method.csv',  emit: method
        path 'produced_metadata.json', emit: metadata
        path "${task.tag}.RDS" optional !params.raw

    script:
    save_raw     = params.raw ? "--save-raw"      : ""
    raw_location = params.raw ? "${task.tag}.RDS" : ""
    """
    covidestim-batch \
      --input $tractData \
      --key $params.key \
      --metadata $metadata \
      --attempts 1 \
      --cpus $task.cpus \
      --always-optimize \
      --save-summary  summary.csv \
      --save-warning  warning.csv \
      --save-optvals  optvals.csv \
      --save-method   method.csv \
      --save-metadata produced_metadata.json \
      $save_raw $raw_location
    """
}

