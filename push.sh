#!/bin/bash

git add .
git commit -m $(date +%Y%m%d)
git push origin master
