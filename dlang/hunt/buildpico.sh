#!/bin/bash

rm -rf picohttpparser
git clone https://github.com/h2o/picohttpparser.git hunt-pico/picohttpparser
cp hunt-pico/patches/Makefile hunt-pico/picohttpparser/
cd hunt-pico/picohttpparser
make package
