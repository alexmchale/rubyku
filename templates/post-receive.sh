#!/bin/bash -l

# Fail on errors, be verbose.
set -o errexit
set -o verbose

# Get into the project directory w/o GIT_DIR there to mess us up.
cd ..
unset GIT_DIR
export RAILS_ENV=production
app=$( basename `pwd` )

# Get the revspec for this push.
while read oval nval ref ; do
  if expr "$ref" : "^refs/heads/"; then
    if expr "$oval" : '0*$' >/dev/null; then
      revspec=$nval
    else
      revspec=$oval..$nval
    fi
  fi
done

# Detect if the bundle changed.
if [ git diff --name-only "$revspec" | egrep '^Gemfile.lock$' > /dev/null 2>&1 ]; then
  bundle_changed="1"
else
  bundle_changed="0"
fi

# Detect if the system packages changed.
if [ git diff --name-only "$revspec" | egrep '^config/rubyku.yml$' > /dev/null 2>&1 ]; then
  system_packages_changed="1"
else
  system_packages_changed="0"
fi

# Ensure we've got a clean repository on the latest commit.
git checkout
git reset --hard HEAD
git clean -df

# Install any new required system packages.
if [ "$system_packages_changed" = "1" ]; then
  sudo apt-get -y update
  sudo apt-get -y install $( ruby -r yaml -e 'puts YAML.load(File.read("config/rubyku.yml"))["system_packages"].map(&:strip).join(" ") rescue Exception' )
fi

# Install the new bundle if changed.
if [ "$bundle_changed" = "1" ]; then
  bundle install --without development test
fi

# Update wrappers for this application.
rvm alias create "$app" "`cat .ruby-version`"

# Update the application.
bundle exec rake upgrade

# Reload and bounce the service.
port=$( $HOME/.port_numbers/get_port )
user=$( whoami )
sudo /usr/local/bin/foreman export upstart /etc/init \
  --app "$app"                        \
  --log "$HOME/.logs"                 \
  --port "$port"                      \
  --user "$user"                      \
  --run "$HOME/.pids"
