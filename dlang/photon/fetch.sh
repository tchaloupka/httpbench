#!/bin/bash

if [ ! -d ./photon ]
then
    git clone --recurse-submodules https://github.com/DmitryOlshansky/photon.git
    cp patched_support.d photon/src/photon/linux/support.d
fi
