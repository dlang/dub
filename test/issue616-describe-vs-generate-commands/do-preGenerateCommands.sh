#!/bin/sh
if [ -n "${dub_issue616}" ]; then
    echo 'Fail! preGenerateCommands recursion detected!' >&2
    exit 0  # Don't return a non-zero error code here. This way the test gives a better diagnostic.
fi

echo preGenerateCommands: DUB_PACKAGES_USED=$DUB_PACKAGES_USED >&2

export dub_issue616=true
$DUB describe --data-list --data=import-paths >&2
