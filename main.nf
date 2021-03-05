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

include {jhuData; jhuStateData} from './src/inputs'
include {filterTestTracts; splitTractData} from './src/inputs-utils'
include {runTractSampler; runTractOptimizer} from './src/modelrunners'
include {publishStateResults; publishCountyResults} from './src/outputs'

def collectCSVs(chan, fname) {
    chan.collectFile(
        name: fname,
        storeDir: params.outdir,
        keepHeader: true,
        skip: 1
    )
}

workflow {
main:
    generateData = params.key == "fips" ? jhuData : jhuStateData

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
      generateData | filterTestTracts | splitTractData | flatten | take(params.n) | runTract
    else
      generateData | splitTractData | flatten | take(params.n) | runTract

    if (runner == "runTractOptimizer") {
        summary = collectCSVs(runTractOptimizer.out.summary, 'summary.csv')
        warning = collectCSVs(runTractOptimizer.out.warning, 'warning.csv')
        optvals = collectCSVs(runTractOptimizer.out.optvals, 'optvals.csv')
        method  = collectCSVs(runTractOptimizer.out.method,  'method.csv' )
    } else {
        summary = collectCSVs(runTractSampler.out.summary, 'summary.csv')
        warning = collectCSVs(runTractSampler.out.warning, 'warning.csv')
        optvals = collectCSVs(runTractSampler.out.optvals, 'optvals.csv')
        method  = collectCSVs(runTractSampler.out.method,  'method.csv' )
    }

    if (params.key == "fips") {
        input   = jhuData.out.data
        rejects = jhuData.out.rejects

        publishCountyResults(summary, input, rejects, warning, optvals)
    } else {
        input   = jhuStateData.out.data
        rejects = jhuStateData.out.rejects

        publishStateResults(summary, input, rejects, warning, optvals, method)
    }

    collectCSVs(rejects, 'rejects.csv')

emit:
    summary = summary
    warning = warning
    optvals = optvals
    rejects = rejects
}
