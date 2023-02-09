#!/bin/bash

cd ${CURR_DIR}/issue1636-betterC-dub-test

${DUB} test | grep -c "TEST_WAS_RUN" > /dev/null
