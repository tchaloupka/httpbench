#!/bin/bash
nginx -c $(pwd)/nginx.conf -g "worker_processes $1;"
