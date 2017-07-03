#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
${DUB} search 2>/dev/null && exit 1
${DUB} search nonexistent123456789package 2>/dev/null && exit 1
${DUB} search dub | grep -q '^dub' || exit 1
