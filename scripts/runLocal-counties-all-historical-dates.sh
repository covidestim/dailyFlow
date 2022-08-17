#!/usr/bin/bash

# NOTE: Execute this from the repository root.

set -euxo

scripts/runLocal-counties-historical.sh 0 2022-07-21 &&
scripts/runLocal-counties-historical.sh 1 2022-07-14 &&
scripts/runLocal-counties-historical.sh 2 2022-07-07 &&
scripts/runLocal-counties-historical.sh 3 2022-06-30 &&
scripts/runLocal-counties-historical.sh 7 2022-06-02 &&
scripts/runLocal-counties-historical.sh 11 2022-05-05 &&
scripts/runLocal-counties-historical.sh 15 2022-04-07 &&
scripts/runLocal-counties-historical.sh 20 2022-03-03 &&
scripts/runLocal-counties-historical.sh 24 2022-02-03 &&
scripts/runLocal-counties-historical.sh 28 2022-01-06 &&
scripts/runLocal-counties-historical.sh 29 2021-12-30
