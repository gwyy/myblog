#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"
# github pull
git pull --force
# Build the project.
hugo --minify
# 编译代码
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o blog

