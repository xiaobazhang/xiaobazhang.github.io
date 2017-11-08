#!/bin/bash

git add ./_posts
git add ./public
git commit -m $(date +%Y%m%d)
git push origin master

