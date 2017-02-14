#!/bin/sh

${DUB} build --bare main --override-config a/success || exit 1
