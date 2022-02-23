#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"
# 清理工作
rm -rf public/
rm -rf blog
rm -rf resources/
#rm -rf node_modules
#rm -rf package-lock.json
# github pull
git fetch --all
git reset --hard origin/main
git pull
#git pull themes
#cd  themes/hugo-theme-cleanwhite
#git reset --hard origin/master
#cd ../../
# Build the project.
#/usr/local/bin/cnpm i
/root/repository/go/bin/hugo --minify
#/usr/local/bin/cnpm run algolia

# 编译代码
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 /usr/bin/go build -o blog

# 生成docker镜像
docker build  --tag myblog:latest .

#更新docker-compose
#第一次需要先创建网络
docker-compose down
docker-compose up -d

#清理工作 删除tag为none的无用image
docker images | grep none | awk '{print $3}' | xargs docker rmi
docker system prune -f

