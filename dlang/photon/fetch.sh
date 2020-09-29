#!/bin/bash

if [ ! -d ./photon ]
then
    git clone --recurse-submodules https://github.com/DmitryOlshansky/photon.git
fi

if ! patch -Rsfl -p1 --dry-run -d photon < fixes.patch; then
    patch -p1 -l -d photon < fixes.patch
fi
