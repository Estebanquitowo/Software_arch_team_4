#!/bin/sh
set -eu

# The host checkout remains read-only, including Gemfile.lock. Bundler and Rails
# may write only to this disposable copy in the test container.
mkdir -p /work
tar -C /source --exclude=./.git --exclude=./.env --exclude=./tmp --exclude=./log -cf - . | tar -C /work -xf -
cd /work
exec bin/rails test "$@"
