---
title: "性能压测工具 wrk 使用"
date: 2020-10-12T11:40:02+08:00
lastmod: 2020-10-12T11:40:02+08:00
keywords: ["压测工具","网络","wrk"]
description: "wrk 是一款针对 Http 协议的基准测试工具"
tags: ["linux运维"]
categories: ["运维工具"]
author: "梁天"
---
wrk 是一款针对 Http 协议的基准测试工具，它能够在单机多核 CPU 的条件下，使用系统自带的高性能 I/O 机制，如 epoll，kqueue 等，通过多线程和事件模式，对目标机器产生大量的负载。
<!--more-->
名词解释
1. QPS: 　QPS（Query per second 每秒处理完的请求数）
---
## 什么是wrk
看下他GitHub上的介绍：https://github.com/wg/wrk
>wrk is a modern HTTP benchmarking tool capable of generating significant load when run on a single multi-core CPU. It combines a multithreaded design with scalable event notification systems such as epoll and kqueue.

wrk 是一款针对 Http 协议的基准测试工具，它能够在单机多核 CPU 的条件下，使用系统自带的高性能 I/O 机制，如 epoll，kqueue 等，通过多线程和事件模式，对目标机器产生大量的负载。

> PS: 其实，wrk 是复用了 redis 的 ae 异步事件驱动框架，准确来说 ae 事件驱动框架并不是 redis 发明的, 它来至于 Tcl 的解释器 jim, 这个小巧高效的框架, 因为被 redis 采用而被大家所熟知。

wrk 的优势：
1. 轻量级性能测试工具;
2. 安装简单（相对 Apache ab 来说）;
3. 学习曲线基本为零，几分钟就能学会咋用了；
4. 基于系统自带的高性能 I/O 机制，如 epoll, kqueue, 利用异步的事件驱动框架，通过很少的线程就可以压出很大的并发量；

劣势:

wrk 目前仅支持单机压测，后续也不太可能支持多机器对目标机压测，因为它本身的定位，并不是用来取代 JMeter, LoadRunner 等专业的测试工具，wrk 提供的功能，对我们后端开发人员来说，应付日常接口性能验证还是比较友好的。

### wrk的安装
mac:
```shell
brew install wrk
```

linux:
```shell
git clone https://github.com/wg/wrk.git wrk
cd wrk
make
# 将可执行文件移动到 /usr/local/bin 位置
sudo cp wrk /usr/local/bin
```
简单使用
```shell
wrk -t12 -c400 -d30s http://www.baidu.com
```
wrk -t12 -c400 -d30s http://www.baidu.com

### wrk 命令参数说明
除了上面简单示例中使用到的子命令参数，wrk 还有其他更丰富的功能，命令行中输入 wrk --help, 可以看到支持以下子命令：

```shell
wrk --help
Usage: wrk <options> <url>                           
  Options:                                           
    -c, --connections <N>  Connections to keep open   跟服务器建立并保持的TCP连接数量  总的连接数（每个线程处理的连接数=总连接数/线程数）
    -d, --duration    <T>  Duration of test           压测时间  
    -t, --threads     <N>  Number of threads to use   使用多少个线程进行压测
                                                       
    -s, --script      <S>  Load Lua script file       指定Lua脚本路径  
    -H, --header      <H>  Add header to request      为每一个HTTP请求添加HTTP头
        --latency          Print latency statistics   在压测结束后，打印延迟统计信息
        --timeout     <T>  Socket/request timeout     超时时间
    -v, --version          Print version details      打印正在使用的wrk的详细版本信息
                                                       
  Numeric arguments may include a SI unit (1k, 1M, 1G)
  Time arguments may include a time unit (2s, 2m, 2h)<N>代表数字参数，支持国际单位 (1k, 1M, 1G) <T>代表时间参数，支持时间单位 (2s, 2m, 2h)

```
关于线程数，并不是设置的越大，压测效果越好，线程设置过大，反而会导致线程切换过于频繁，效果降低，一般来说，推荐设置成压测机器 CPU 核心数的 2 倍到 4 倍就行了。

#### 测试报告
执行压测命令:
```shell
wrk -t12 -c400 -d30s --latency http://www.baidu.com
```
执行上面的压测命令，30 秒压测过后，生成如下压测报告：
```shell
Running 30s test @ http://www.baidu.com   （压测时间30s）
  12 threads and 400 connections  （共12个测试线程，400个连接）
（平均值） （标准差） （最大值）（正负一个标准差所占比例）
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency   386.32ms  380.75ms   2.00s    86.66%   (延迟
    Req/Sec    17.06     13.91   252.00     87.89%  （每秒请求数
  Latency Distribution   （延迟分布
     50%  218.31ms
     75%  520.60ms
     90%  955.08ms
     99%    1.93s
  4922 requests in 30.06s, 73.86MB read   (30.06s内处理了4922个请求，耗费流量73.86MB)
  Socket errors: connect 0, read 0, write 0, timeout 311  （发生错误数
Requests/sec:    163.76  (QPS 163.76,即平均每秒处理请求数为163.76)
Transfer/sec:      2.46MB   (平均每秒流量2.46MB)
```
标准差啥意思？标准差如果太大说明样本本身离散程度比较高，有可能系统性能波动较大。标准差为0 就是一条直线

### 使用 Lua 脚本进行复杂测试

您可能有疑问了，你这种进行 GET 请求还凑合，我想进行 POST 请求咋办？而且我想每次的请求参数都不一样，用来模拟用户使用的实际场景，又要怎么弄呢？

对于这种需求，我们可以通过编写 Lua 脚本的方式，在运行压测命令时，通过参数 --script 来指定 Lua 脚本，来满足个性化需求。

#### wrk 对 Lua 脚本的支持
wrk 支持在三个阶段对压测进行个性化，分别是启动阶段、运行阶段和结束阶段。每个测试线程，都拥有独立的Lua 运行环境。

启动阶段:
```shell
function setup(thread)
```
在脚本文件中实现 setup 方法，wrk 就会在测试线程已经初始化，但还没有启动的时候调用该方法。wrk会为每一个测试线程调用一次 setup 方法，并传入代表测试线程的对象 thread 作为参数。setup 方法中可操作该 thread 对象，获取信息、存储信息、甚至关闭该线程。
```shell
thread.addr             - get or set the thread's server address
thread:get(name)        - get the value of a global in the thread's env
thread:set(name, value) - set the value of a global in the thread's env
thread:stop()           - stop the thread
```
运行阶段:
```shell
function init(args)
function delay()
function request()
function response(status, headers, body) 
```
+ init(args): 由测试线程调用，只会在进入运行阶段时，调用一次。支持从启动 wrk 的命令中，获取命令行参数；
+ delay()： 在每次发送请求之前调用，如果需要定制延迟时间，可以在这个方法中设置；
+ request(): 用来生成请求, 每一次请求都会调用该方法，所以注意不要在该方法中做耗时的操作；
+ response(status, headers, body): 在每次收到一个响应时被调用，为提升性能，如果没有定义该方法，那么wrk不会解析 headers 和 body

结束阶段：
```shell
function done(summary, latency, requests)
```
done() 方法在整个测试过程中只会被调用一次，我们可以从给定的参数中，获取压测结果，生成定制化的测试报告。

#### 自定义 Lua 脚本中可访问的变量以及方法：
变量：wrk
```shell
wrk = {
    scheme  = "http",
    host    = "localhost",
    port    = 8080,
    method  = "GET",
    path    = "/",
    headers = {},
    body    = nil,
    thread  = <userdata>,
  }
```
以上定义了一个 `table` 类型的全局变量，修改该 wrk 变量，会影响所有请求。

方法：
1. wrk.fomat
2. wrk.lookup
3. wrk.connect

上面三个方法解释如下
```shell
function wrk.format(method, path, headers, body)
 
    wrk.format returns a HTTP request string containing the passed parameters
    merged with values from the wrk table.
    # 根据参数和全局变量 wrk，生成一个 HTTP rquest 字符串。
 
function wrk.lookup(host, service)
 
    wrk.lookup returns a table containing all known addresses for the host
    and service pair. This corresponds to the POSIX getaddrinfo() function.
    # 给定 host 和 service（port/well known service name），返回所有可用的服务器地址信息。
 
function wrk.connect(addr)
 
    wrk.connect returns true if the address can be connected to, otherwise
    it returns false. The address must be one returned from wrk.lookup().
    # 测试给定的服务器地址信息是否可以成功创建连接
```
#### 案例：通过 Lua 脚本压测示例

调用 POST 接口：
```shell
wrk.method = "POST"
wrk.body   = "foo=bar&baz=quux"
wrk.headers["Content-Type"] = "application/x-www-form-urlencoded"
```
注意: wrk 是个全局变量，这里对其做了修改，使得所有请求都使用 POST 的方式，并指定了 body 和 Content-Type头。

自定义每次请求的参数：
```shell
request = function()
   uid = math.random(1, 10000000)
   path = "/test?uid=" .. uid
   return wrk.format(nil, path)
end
```
在 request 方法中，随机生成 1~10000000 之间的 uid，并动态生成请求 URL.

每次请求前，延迟 10ms:
```shell
function delay()
   return 10
end
```
请求的接口需要先进行认证，获取 token 后，才能发起请求，咋办？

```shell
token = nil
path  = "/auth"
 
request = function()
   return wrk.format("GET", path)
end
 
response = function(status, headers, body)
   if not token and status == 200 then
      token = headers["X-Token"]
      path  = "/test"
      wrk.headers["X-Token"] = token
   end
end
```
上面的脚本表示，在 token 为空的情况下，先请求 /auth 接口来认证，获取 token, 拿到 token 以后，将 token 放置到请求头中，再请求真正需要压测的 /test 接口。

压测支持 HTTP pipeline 的服务：
```shell
init = function(args)
   local r = {}
   r[1] = wrk.format(nil, "/?foo")
   r[2] = wrk.format(nil, "/?bar")
   r[3] = wrk.format(nil, "/?baz")
 
   req = table.concat(r)
end
 
request = function()
   return req
end
```

通过在 init 方法中将三个 HTTP请求拼接在一起，实现每次发送三个请求，以使用 HTTP pipeline。　

