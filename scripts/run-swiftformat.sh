#! /bin/sh

# Set PWD to script directory
cd "${0%/*}"

export PODS_ROOT=../Pods
export SRCROOT=../Workflows

./swiftformat.sh

export SRCROOT=../WorkflowsTests
./swiftformat.sh

cd -
