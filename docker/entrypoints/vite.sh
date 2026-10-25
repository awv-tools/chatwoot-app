#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

git config --global --add safe.directory /app
export PATH=/usr/local/lib/ruby/gems/3.4.0/bin:$PATH
# Same bundler the lockfile was bundled with, so upstream bumps don't break bin/vite
gem install bundler -v "$(tail -1 /app/Gemfile.lock | tr -d ' ')"

# ADICIONE ESTA LINHA - instala as gems do projeto
bundle install --gemfile /app/Gemfile

pnpm store prune
pnpm install --force

echo "Ready to run Vite development server."

exec "$@"