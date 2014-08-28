#!/bin/bash

# Initialize the git repository, if needed
if [ ! -d "%%app_name%%" ]; then
  git init %%app_name%%
fi

# Configure the git repository
cd %%app_name%%
git config receive.denyCurrentBranch ignore
echo %%inject:post-receive.sh%% > .git/hooks/post-receive
chmod u+x .git/hooks/post-receive

# Write database.yml
mkdir -p config
echo %%inject:postgresql-database.yml%% > config/database.yml
