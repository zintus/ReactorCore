#! /bin/sh

# Set PWD to script directory
cd "${0%/*}"

export PODS_ROOT=../Pods
export SRCROOT=../ReactorCore

./swiftformat.sh

export SRCROOT=../ReactorCoreTests
./swiftformat.sh

cd -
