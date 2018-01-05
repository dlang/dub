#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
$DUB --version | grep -qF 'DUB version'
