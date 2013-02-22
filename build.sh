#!/bin/sh
rdmd --build-only -ofdub -g -debug -Isource -L-lcurl $* source/app.d
