#!/bin/bash -l

cd %%app_root%%/.git
echo master | ./hooks/post-receive
