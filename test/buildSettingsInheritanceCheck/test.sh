#!/usr/bin/env bash

set -e

$DUB test --root=diamond/p0 -v
$DUB test --root=commonDep/p0 -v
$DUB test --root=commonDep/p1 -v
