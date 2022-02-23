---
title:       "第一篇博文，纪念一下"
description: "几经波折后，博客终于稳定下来了，几年一下"
date:        2022-02-23
author:      "梁天"
image:       ""
tags:        ["life"]
categories:  ["life" ]
---

这是新博客的第一篇博文，很有纪念意义，也许多年后回来再看，这里就是梦开始的地方。😄
<!--more-->
### 背景
&nbsp;&nbsp;域名在手上也有5、6年了，一直没有一个正儿八经的博客。从以前的csdn到后面的cnblogs，然后又到WordPress，hexo，最后到了hugo，回想起来真是的一路艰辛啊。每次都是搞了一段时间就关掉了。最近又打算重新开始搞，也断断续续折腾了好久，从2021年底折腾到过了年2月份都要过完了，终于算是把博客完全搞定了。希望这次能一直坚持下来。

&nbsp;&nbsp;最近事情一直比较忙，忙着新的一年制定计划，推动业务。实在是没有多少精力来折腾博客。只能每周周末，或者每天不太忙的时候搞搞。从动态博客迁移到静态博客也是下了一段时间的决心的。主要考虑还是动态博客迁移比较麻烦。我又是个比较爱折腾的人，每次迁移成本也是比较高。并且也没有markdown方便，后面改成静态博客了，只要换个theme,所有的博文都在，这次也算是第一次搞静态博客，整体搞下来还是挺有收货的。

### 调研
&nbsp;&nbsp;确定要换成静态博客的时候还是调研了好几款不错的开源博客，例如hexo、vuepress、docsify、hugo。最后本地也测试了几款还是选择了hugo。一个主要的原因是本身就是偏后端侧的开发。而且最近主要是做golang这方面，所以先天就会比较偏向hugo。其他的hexo和docsify都是nodejs的技术路线，感兴趣的朋友也可以看看。vuepress是比较新的静态博客系统。不过整体看下来还是比较单一的。用的人不多。

&nbsp;&nbsp;当然hugo也不是十全十美的。最大的问题就是模板比较少。没有hexo那么花哨绚丽的模板。一开始我用的是 [老赵](https://www.zhaohuabing.com/) 的 [hugo-theme-cleanwhite](https://github.com/zhaohuabing/hugo-theme-cleanwhite) 模板。还给老赵搞了个Twikoo评论组件。不过人总是喜欢折腾。最近换了even模板。整体简洁不少。还是比较喜欢的。

### 发布流程
&nbsp;&nbsp;最后说下我博客整体构建和发布方案吧。其实一开始就是想着每次我在Markdown上写好博文后，通过github push上去后就不用管了，接下来一套编译打包流程就会自动处理。奔着这个目标也是折腾了不少时间。下面具体说下步骤：

#### 1、建立仓库
首先肯定是要有个github 仓库的。用作你的博客载体。这是我的[博客仓库](https://github.com/gwyy/myblog) 。大家可以参考下。

#### 2、构建workflows
代码仓库里新建一个 `.github` 文件夹。里面新建个 `workflows` 文件夹。然后建立一个空的  yaml 文件。作为每次触发github Actions的配置文件。至于github Actions 是什么 大家可以参考阮一峰大神的这篇文章 [GitHub Actions 入门教程](https://www.ruanyifeng.com/blog/2019/09/getting-started-with-github-actions.html)  简单说下就是类似一个高级版的webhook, 可以push后做一些你指定的事情。 下面看下我的workflows 配置。
```shell
name: Blog
on:  #触发器
  push:  #每次 main push的时候触发
    branches: [ main ]
jobs:
  build:
    name: Blog  #执行名称
    runs-on: ubuntu-latest  #运行所需要的虚拟机环境
    timeout-minutes: 60
    steps:
    - name: Build Blog
      env:
        USER: ${{ secrets.SERVER_USER }}
        KEY: ${{ secrets.SERVER_KEY }}
        DOMAIN: ${{ secrets.SERVER_DOMAIN }}
      run: |
        mkdir ~/.ssh
        echo "$KEY" | tr -d '\r' > ~/.ssh/id_ed25519
        chmod 400 ~/.ssh/id_ed25519
        eval "$(ssh-agent -s)"
        ssh-add ~/.ssh/id_ed25519
        ssh-keyscan -H $DOMAIN >> ~/.ssh/known_hosts
        ssh $USER@$DOMAIN "cd /root/wwwroot/myblog && /bin/bash deploy.sh"
```
整体代码很简单，我也加了一些备注，主要就是代码推送到github之后，通过设置好的用户名和key,让github远程链接我的服务器，然后触发 `deploy.sh` 这个shell。当然了这个功能远远不止这些，它还可以帮你docker打包镜像并且自动推送到dockerHub。只不过这里我仅仅当做一个除触发器来使用了。

#### 3、deploy
最核心的就是执行deploy.sh环节了，大致分为三块：

##### 1、拉取代码
清理一些编译好的二进制文件，和静态博客目录，然后拉取最新代码。
```shell
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
```
##### 2、编译程序
执行 hugo 命令，编译出博客本体， --minify是开启压缩。然后编译执行我写的golang脚本，该脚本做的事情很简单。监听3001端口，并且开启一个静态的httpServer。里面的内容就是我的静态博客
```shell
/root/repository/go/bin/hugo --minify
#/usr/local/bin/cnpm run algolia

# 编译代码
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 /usr/bin/go build -o blog
```
脚本部分代码
```go
r := http.NewServeMux()
r.Handle("/", http.FileServer(http.Dir("/app/public")))
s := &http.Server{
    Addr:         addr,
    Handler:      logger(r),
    ReadTimeout:  30 * time.Second,
    WriteTimeout: time.Minute,
    IdleTimeout:  time.Minute,
}
```

##### 3、打包镜像
最后一步就是执行当前目录里的Dockerfile文件生成镜像。Dockerfile文件内容也很简单，把刚才生成的静态博客目录和刚才编译的golang二进制程序拷贝到镜像体内就完成。 然后docker-compose 关闭并且清理掉镜像。接着重新启动docker-compose。最后做下清理工作。
```shell
# 生成docker镜像
docker build  --tag myblog:latest .

#更新docker-compose
#第一次需要先创建网络
docker-compose down
docker-compose up -d

#清理工作 删除tag为none的无用image
docker images | grep none | awk '{print $3}' | xargs docker rmi
docker system prune -f
```
这里重点说下docker-compose部分。

docker-compose里会启动一个实例来启动当前镜像。并且会打上一些traefik的标签。[traefik](https://doc.traefik.io/traefik/) 是一个边缘路由，和docker k8s深度结合。可以通过动态配置，在容器上打标签的方式就能配置好对应的规则。并且支持自动申请https证书、自动续费的功能。

下面看下docker-compose.yaml内容：
```shell
version: '3'
services:
  blog:
    image: myblog:latest
    restart: always
    networks:
      - proxy-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.middlewares.test-http-cache.plugin.httpCache.maxTtl=600"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
      - "traefik.http.routers.blog.middlewares=redirect-to-https@docker"
      - "traefik.http.routers.blog.rule=Host(`liangtian.me`)"
      - "traefik.http.routers.blog.entrypoints=websecure"
      - "traefik.http.routers.blog.tls=true"
      - "traefik.http.routers.blog.tls.certresolver=letsencryptresolver"
      - "traefik.http.services.blog.loadbalancer.server.port=3001"

networks:
  proxy-net:
    external: true
```
可以看到，我这里创建一个虚拟网络，这样每次容器上线后会触发traefik事件。lables里面就是traefik的一些配置，开启了http缓存，设置了https规则等。有兴趣的朋友可以研究下。

到这里整个流程就完成了。这套方案的好处是基本上不依赖任何三方中间件。任意换一台服务器只要能够连接上github和dockerhub 基本上就能很快的跑起来我的博客。其实可以把编译工作的前半部分golang打包部分也做到github workflows里，这里就看大家怎么喜欢怎么来就好了。

今天就先写这么多吧，有什么问题大家可以给我留言。😄

