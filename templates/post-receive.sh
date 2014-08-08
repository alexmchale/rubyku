#!/bin/bash -l

# Fail on errors, be verbose.
set -o errexit
set -o verbose

# Get into the project directory w/o GIT_DIR there to mess us up.
cd ..
unset GIT_DIR

# Ensure we've got a clean repository on the latest commit.
git checkout
git reset --hard HEAD
git clean -df

# Install any new required system packages.
if [ -f config/rubyku.yml ]; then
  sudo apt-get -y update
  sudo apt-get -y install $( ruby -r yaml -e 'puts YAML.load(File.read("config/rubyku.yml"))["system_packages"].map(&:strip).join(" ") rescue Exception' )
fi

# Update the application.
bundle
bundle exec rake upgrade
