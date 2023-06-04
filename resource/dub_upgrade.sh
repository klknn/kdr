#!/bin/bash

set -euo pipefail

dub upgrade

for d in $(ls bin)
do
  cd "bin/${d}"
  dub upgrade
  cd -
done
