#!/bin/bash

set -euo pipefail

for d in $(ls bin)
do
  if [ "${d}" = "comp1" ]
  then
    continue
  fi
  cd "bin/${d}"
  dub run dplug:dplug-build -b=release -- --final -c VST3
  cd -
done
