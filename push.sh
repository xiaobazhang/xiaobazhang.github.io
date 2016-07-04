#!/bin/bash

git add .
git add -A
git commit -m $(date +%Y%m%d)
git push origin master
