#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"
# 清理工作
rm -rf public/
rm -rf blog
rm -rf node_modules
rm -rf package-lock.json
# github pull
git reset --hard origin/main
#git pull themes
#cd  themes/hugo-theme-cleanwhite
#git reset --hard origin/master
#cd ../../
# Build the project.
npm i
hugo --minify
npm run algolia

# 编译代码
go build -o blog

# 生成docker镜像
