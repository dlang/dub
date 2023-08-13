#!/bin/bash

cd ${CURR_DIR}/issue2684-recipe-file
${DUB} | grep -c "This was built using dub.json" > /dev/null
${DUB} --recipe=dubWithAnotherSource.json | grep -c "This was built using dubWithAnotherSource.json" > /dev/null