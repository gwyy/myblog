### 创建新项目

```bash
hugo new site myblog
```

### 添加主题

找到相关的 GitHub 地址，创建目录 themes，在 themes 目录里把皮肤 git clone 下来：
主题介绍： https://themes.gohugo.io/themes/hugo-theme-cleanwhite/
```shell
//安装clean white 
git submodule add https://github.com/zhaohuabing/hugo-theme-cleanwhite.git themes/hugo-theme-cleanwhite
cp -r hugo-theme-cleanwhite/exampleSite/** ../
echo theme = \"hugo-theme-cleanwhite\" >> config.toml

//设置搜索
npm init
npm install atomic-algolia --save
//打开 package.json
"algolia": "atomic-algolia"
//重新生成
hugo
//在 .env 文件里写入
ALGOLIA_APP_ID={{ YOUR_APP_ID }}
ALGOLIA_ADMIN_KEY={{ YOUR_ADMIN_KEY }}
ALGOLIA_INDEX_NAME={{ YOUR_INDEX_NAME }}
ALGOLIA_INDEX_FILE={{ PATH/TO/algolia.json }}
//执行
npm run algolia
//添加到站点内
algolia_search = true
algolia_appId = {{ YOUR_APP_ID }}
algolia_indexName = {{ YOUR_INDEX_NAME }}
algolia_apiKey = {{ YOUR_ADMIN_KEY }}
```

### 写文章

```shell
//Drafts do not get deployed; once you finish a post, update the header of the post to say draft: false. 
hugo new post/my-first-post.md
//写入
content/post/hugoblog-init.md
//前台打开
http://localhost:1313/posts/hugoblog-init/
```

### 命令

```shell

#启动
hugo server -D

#查看版本
hugo version
 
#版本和环境详细信息
hugo env

#创建文章
hugo new post/my-first-post.md

#编译生成静态文件
hugo
  -D 包括草稿页面

#编译生成静态文件并启动web服务
hugo server
 --bind="127.0.0.1"    服务监听IP地址；
  -p, --port=1313       服务监听端口；
  -w, --watch[=true]      监听站点目录，发现文件变更自动编译；
  -D, --buildDrafts     包括被标记为draft的文章；
  -E, --buildExpired    包括已过期的文章；
  -F, --buildFuture     包括将在未来发布的文章；
  -b, --baseURL="www.datals.com"  服务监听域名；
  --log[=false]:           开启日志；
  --logFile="/var/log/hugo.log":          log输出路径；
  -t, --theme=""          指定主题；
  -v, --verbose[=false]: 输出详细信息

执行hugo命令，站点目录下会新建文件夹public/，生成的所有静态网站页面都会存储到这个目录，
如果使用Github pages来作为博客的Host，你只需要将public/里的文件上传就可以。
如果使用nginx作为web服务配置root dir 指向public/ 即可；

```

//参考其他皮肤
https://github.com/Nov8nana/hugo-blog