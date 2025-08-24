#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

git config --global --add safe.directory /app

export PATH=/usr/local/lib/ruby/gems/3.4.0/bin:$PATH
gem install bundler -v 2.5.11

pnpm store prune
pnpm install --force

echo "Ready to run Vite development server."

exec bundle _2.5.11_ exec "$@"
