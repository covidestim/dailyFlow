#!/usr/bin/env nextflow

// Enable DSL2
nextflow.enable.dsl = 2

params.testtracts   = false    // By default, run all tracts
params.PGCONN       = "null"   // By default, there's no DB connection
params.timemachine  = false    // By default, use latest data
params.alwayssample = false    // By default, fall back to the optimizer for states
params.alwaysoptimize = false  // By default, use the sampler for states
params.n            = -1       // By default, run all tracts
params.ngroups      = 10000000 // By default, each tract gets its own NF process
params.branch       = "latest" // Branch of model to run - must be on Docker Hub
params.key          = "fips"   // "fips" for county runs, "state" for state runs
params.raw          = false    // Output raw `covidestim-result` object as .RDS?
params.s3pub        = false    // Don't upload to S3 by default
params.splicedate   = false    // By default, don't do any custom date splicing
                               //   for state-level runs. This still means that
                               //   CTP data will prefill JHU data.

// Where a set of backup LM objects for creating synthetic intervals resides.
params.syntheticBackup = 's3://covidestim/synthetic-backup/backup.RDS'

include {fayetteVaxData; fayetteStateVaxData} from './src/inputs'
include {filterTestTracts; splitTractData} from './src/inputs-utils'
include {runTractSampler; runTractOptimizer} from './src/modelrunners'
include {makeSyntheticIntervals} from './src/synthetic-intervals'
include {publishStateResults; publishCountyResults} from './src/outputs'

def collectCSVs(chan, fname) {
    chan.collectFile(
        name: fname,
        storeDir: params.outdir,
        keepHeader: true,
        skip: 1
    )
}

// Joins two channels and emits a third channel of lists, of the form
// [key, chan1Item, chan2Item]
//
// Assumption: chan1 and chan2 are both emitting file paths
def tupleChan(chan1, chan2) {
    chan1Lists = chan1.flatten().map{ [it.getSimpleName(), it] }
    chan2Lists = chan2.flatten().map{ [it.getSimpleName(), it] }

    chan1Lists.join(chan2Lists, failOnDuplicate: true, failOnMismatch: true)
}

def collectJSONs(chan, fname) {
    def slurp = new groovy.json.JsonSlurper()

    return chan.reduce( [] ) { listA, jsonFileB ->
        def b = slurp.parse(jsonFileB)

        // Returns `false` if `listA` was not modified
        def successful = listA.addAll(b)

        if (!successful)
          throw new Exception("No items were added to accumulator")

        return listA
    }
    .map{ it -> groovy.json.JsonOutput.toJson(it) }
    .collectFile( name: fname, storeDir: params.outdir )
}

workflow {
main:
    // Choose which data cleaning process to use based on whether state-level
    // or county-level data is desired
    generateData = params.key == "fips" ? fayetteVaxData : fayetteStateVaxData

    // Rules for choosing which runner is to be used
    runner = ""
    if (params.alwayssample) {
      runTract = runTractSampler
      runner = "runTractSampler"
    } else if (params.alwaysoptimize) {
      runTract = runTractOptimizer
      runner = "runTractOptimizer"
    } else {
      runTract = params.key == "fips" ? runTractOptimizer   : runTractSampler
      runner   = params.key == "fips" ? "runTractOptimizer" : "runTractSampler"
    }

    if (params.testtracts)
      inputData = generateData | filterTestTracts | splitTractData //| flatten | take(params.n) | runTract
    else
      inputData = generateData | splitTractData // | flatten | take(params.n) | runTract

    tupleChan(splitTractData.out.timeseries, splitTractData.out.metadata) |
      take(params.n) | runTract

    // You can't refer directly to the `runTract` object for some reason, so
    // this branch is here simply to refer to the correct object when collapsing
    // all of the summary/warning/optvals/method csv's into four large .csv 
    // files.
    if (runner == "runTractOptimizer") {
        summary  = collectCSVs(runTractOptimizer.out.summary,   'summary.csv')
        warning  = collectCSVs(runTractOptimizer.out.warning,   'warning.csv')
        optvals  = collectCSVs(runTractOptimizer.out.optvals,   'optvals.csv')
        method   = collectCSVs(runTractOptimizer.out.method,    'method.csv' )
        metadata = collectJSONs(runTractOptimizer.out.metadata, 'postrun_metadata.json')
    } else {
        summary  = collectCSVs(runTractSampler.out.summary,   'summary.csv')
        warning  = collectCSVs(runTractSampler.out.warning,   'warning.csv')
        optvals  = collectCSVs(runTractSampler.out.optvals,   'optvals.csv')
        method   = collectCSVs(runTractSampler.out.method,    'method.csv' )
        metadata = collectJSONs(runTractSampler.out.metadata, 'postrun_metadata.json')
    }

    // Invoke one of the two publishing functions, which reformat the output
    // data for web consumption/DB insertion.
    if (params.key == "fips") {
        input   = fayetteVaxData.out.data
        rejects = fayetteVaxData.out.rejects

        publishCountyResults(summary, input, rejects, warning, optvals, metadata)
    } else {
        input   = fayetteStateVaxData.out.data
        rejects = fayetteStateVaxData.out.rejects

        makeSyntheticIntervals(
            summary,
            metadata, 
            file(params.syntheticBackup)
        )

        summarySynthetic = collectCSVs(
            makeSyntheticIntervals.out.summary,
            'summary_synthetic.csv'
        )

        publishStateResults(
            summarySynthetic,
            input,
            rejects,
            warning,
            optvals,
            method,
            makeSyntheticIntervals.out.metadata
        )

        final_metadata = collectJSONs(makeSyntheticIntervals.out.metadata, 'final_metadata.json')
    }

    // Collect the list of rejected states or counties which were NOT run
    // by any of the runTract* processes.
    collectCSVs(rejects, 'rejects.csv')

emit:
    // Emit the following channels as output from this workflow:
    summary  = summary
    warning  = warning
    optvals  = optvals
    rejects  = rejects
}
