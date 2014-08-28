#!/bin/bash -l

### Helper Functions ###

# Detect if various files changed.
function did_file_change () {
  local filename=$1

  if [ -z "$REVSPEC" ]; then
    git ls-files | egrep "^$filename$" > /dev/null 2>&1
  else
    git diff --name-only "$REVSPEC" | egrep "^$filename$" > /dev/null 2>&1
  fi
}

# Detect if a gem is installed.
function is_gem_installed () {
  local gem=$1
  test "`bundle exec gem list $gem -i 2>&1`" = "true"
}

### Setup ###

# Fail on errors, be verbose.
set -o errexit
#set -o verbose

# Get into the project directory w/o GIT_DIR there to mess us up.
cd ..
unset GIT_DIR

# Prepare the environment.
export RAILS_ENV=production
export APP=$( basename `pwd` )
export PORT=$( $HOME/.port_numbers/get_port )
export USER=$( whoami )

# Get the revspec for this push.
while read oval nval ref ; do
  if expr "$ref" : "^refs/heads/"; then
    if expr "$oval" : '0*$' >/dev/null; then
      export REVSPEC=""
    else
      export REVSPEC="$oval..$nval"
    fi
  fi
done

### Deployment ###

# Ensure we've got a clean repository on the latest commit.
git checkout
git reset --hard HEAD
git clean -df

# Load RVM.
cd .

# Install any new required system packages.
if did_file_change "config/rubyku.yml"; then
  local_packages=$( ruby -r yaml -e 'puts YAML.load(File.read("config/rubyku.yml"))["system_packages"].map(&:strip).join(" ") rescue Exception' )
  sudo DEBIAN_FRONTEND="noninteractive" apt-get -y update -qq
  sudo DEBIAN_FRONTEND="noninteractive" apt-get -y install $local_packages
fi

# Install the new bundle if changed.
if did_file_change "Gemfile.lock"; then
  bundle install --without development test
fi

# Re-load the crontab if needed.
if did_file_change "config/schedule.rb" && is_gem_installed "whenever"; then
  bundle exec whenever --write-crontab "$APP"
fi

# Update wrappers for this application.
rvm alias create "$APP" "`cat .ruby-version`"

# Update the application.
bundle exec rake upgrade

# Reload and bounce the service.
sudo /usr/local/bin/foreman export upstart /etc/init \
  --app "$APP"   \
  --port "$PORT" \
  --user "$USER"
sudo /sbin/initctl reload-configuration
sudo /usr/sbin/service "$APP" restart
