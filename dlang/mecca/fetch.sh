#!/bin/bash

if [ ! -d ./mecca ]
then
    git clone --recurse-submodules https://github.com/weka-io/mecca.git
    dub add-local mecca
fi

if ! patch -Rsfl -p1 --dry-run -d mecca < fixes.patch; then
    patch -p1 -l -d mecca < fixes.patch
fi
