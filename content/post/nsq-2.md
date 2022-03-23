---
title: "nsq 启动流程讲解"
date: 2022-03-02T20:15:02+08:00
lastmod: 2022-03-02T20:15:02+08:00
keywords: ["golang","nsq","源码分析"]
description: "这篇文章我们就正式的开始分析nsq的代码了，上一篇给大家介绍了下nsq的特性和功能。再分析代码的同时，大家可以比对着我写的nsq精注版代码一遍看一遍调试。这样的效果更佳。"
tags: ["nsq","源码分析"]
categories: ["golang","源码分析"]
author: "梁天"
---
这篇文章我们就正式的开始分析nsq的代码了，上一篇给大家介绍了下nsq的特性和功能。再分析代码的同时，大家可以比对着我写的nsq精注版代码一遍看一遍调试。这样的效果更佳。
<!--more-->
nsq精注版地址：[nsq精注版](https://github.com/gwyy/nsq-learn)

下面进入正题，nsqd的主函数位于apps/nsqd.go中的main函数。
在初始化的时候，它使用了第三方进程管理包 go-svc 来托管进程，go-svc有三个方法进行管理：
```go
func main() {
	if err := svc.Run(prg, syscall.SIGINT, syscall.SIGTERM); err != nil {
		logFatal("%s", err)
	}
}
//svc 的init 方法 初始化方法
func (p *program) Init(env svc.Environment) error {
	// 检查是否是windows 服务。。。目测一般时候也用不到，基本上可以直接过
	if env.IsWindowsService() {
		dir := filepath.Dir(os.Args[0])
		return os.Chdir(dir)
	}
	return nil
}
//真正的启动方法
func (p *program) Start() error {
	nsqd, err := nsqd.New(opts)
	if err != nil {
		logFatal("failed to instantiate nsqd - %s", err)
	}
	return nil
}

func (p *program) Stop() error {
	p.once.Do(func() {
		p.nsqd.Exit()
	})
	return nil
}
```
可以看到，man方法实例化了 program 结构体，该结构体从nsq启动一直到销毁贯穿了整个流程，然后实例化了svc包调用了run方法。通过看svc包源码可以发现。svc包内部依次调用了 Init、Start、和接收到指定信号后调用Stop方法。

svc.Init方法主要是判断了在windows下面目录一些特殊处理，可以直接略过。 而svc.Stop方法 主要是调用了program的Exit方法做了一些销毁。我们重点看下 svc.Start方法：
```go
/* 实例化并初始一些配置和默认值 */
opts := nsqd.NewOptions()
```
首先实例化了 Options结构体，该方法内部先获取到了主机名md5,并且作为默认的当前机器id, 然后return了 Options 结构体指针。设置了一些基本的必要的默认参数。

接下来就是设置和解析用户传来的参数，并且中间穿插了打印版本号，如果是打印版本号，打印后就直接退出。用户配置这里也可以通过配置文件进行读取，最后检测配置文件合法性，并且按照优先级依次设置配置文件：
```go
flagSet := nsqdFlagSet(opts)
flagSet.Parse(os.Args[1:])  //解析用户传参
// 初始化load 随机数种子 time.Now().UnixNano()  单位纳秒
rand.Seed(time.Now().UTC().UnixNano())
// 打印版本号,接收命令行参数version  默认值：false 然后直接结束
if flagSet.Lookup("version").Value.(flag.Getter).Get().(bool) {
  fmt.Println(version.String("nsqd"))
  os.Exit(0)
}
// 获取外部的配置文件，解析toml文件格式
var cfg config
configFile := flagSet.Lookup("config").Value.String()
if configFile != "" {
  _, err := toml.DecodeFile(configFile, &cfg)
  if err != nil {
    logFatal("failed to load config file %s - %s", configFile, err)
  }
}
// 检查配置文件
cfg.Validate()
// 采用优先级从高到低依次进行解析，最终
options.Resolve(opts, flagSet, cfg)
```
然后就就是New了一个nsq的实例 ，并且把nsqd对象加入到 progrem中的nsqd属性中去：

```go
nsqd, err := nsqd.New(opts)
if err != nil {
  logFatal("failed to instantiate nsqd - %s", err)
}
//加入到program类里面
p.nsqd = nsqd
```
我们来到 nsqd.New 方法，可以看到该方法做了很多事情，一开始设置了默认路径，并且 设置了默认 log 等一些操作。并且实例化了 NSQD结构体指针。

```go
var err error
// 设置数据缓存路径,主要就是 .dat 文件,记录了 topic 和 channel 的信息
dataPath := opts.DataPath
...
//默认  logger 是否设置,如果没设置 用系统的log
opts.Logger = log.New(os.Stderr, opts.LogPrefix, log.Ldate|log.Ltime|log.Lmicroseconds)
//实例化主类 也是结构体指针
n := &NSQD{
...
}
```
接下里实例化了http客户端，并且实例化了clusterinfo结构体，并且做了一系列的其他的初始化。这里就不一一说明了，直接看代码我有写注释：

```go
//实例化 http_client 结构体，简单包了一层http 	 创建一个 HTTP 客户端，用来从 lookupd 中获取 topic 数据
httpcli := http_api.NewClient(nil, opts.HTTPClientConnectTimeout, opts.HTTPClientRequestTimeout)
//实例化clusterinfo
n.ci = clusterinfo.New(n.logf, httpcli)
...
//给数据目录加锁
err = n.dl.Lock()
// 设置前缀先把统计前缀拼出来存到 opts.StatsdPrefix
if opts.StatsdPrefix != "" {
  opts.StatsdPrefix = prefixWithHost
}
...
// 设置 TLS config
tlsConfig, err := buildTLSConfig(opts)
n.tlsConfig = tlsConfig
...
//初始化tcp server
n.tcpServer = &tcpServer{}
//监听tcp端口
n.tcpListener, err = net.Listen("tcp", opts.TCPAddress)
//监听http端口
n.httpListener, err = net.Listen("tcp", opts.HTTPAddress)
...
//如果开了https
if n.tlsConfig != nil && opts.HTTPSAddress != "" {
  //监听 https
  n.httpsListener, err = tls.Listen("tcp", opts.HTTPSAddress, n.tlsConfig)
}
//这里注意下，端口监听并不会阻塞程序，会直接返回，accept才会阻塞程序
```
到这里，nsqd.New 方法结束，总结下：
1. 开启了主协程，监听了退出信号
2. 初始化并且合并了配置项
3. 实例化的nsq主实例。
4. 给数据目录加锁，监听了tcp和http接口（有https会多个监听https）

我们继续看svc.Start方法。接下来就是加载历史数据到内存：
```go
//加入到program类里面
p.nsqd = nsqd
err = p.nsqd.LoadMetadata()
```
这一步相对来说比较复杂，我们进入到 LoadMetadata函数里面看看：

```go
//使用atomic包中的方法来保证方法执行前和执行后isLoading值的改变
atomic.StoreInt32(&n.isLoading, 1)
defer atomic.StoreInt32(&n.isLoading, 0)
//得到文件路径 nsqd.dat
fn := newMetadataFile(n.getOpts())
//打开文件 读取所有数据
data, err := readOrEmpty(fn)
...
//循环所有topic
for _, t := range m.Topics {
    //使用GetTopic函数通过名字获得topic对象
    topic := n.GetTopic(t.Name)
    //获取当前topic下所有的channel，并且遍历channel，执行的操作与topic基本一致
    for _, c := range t.Channels {
        channel := topic.GetChannel(c.Name)
    }
    //topic启动
    topic.Start()
}
```
首先，我们看到nsq使用了 atomic.StoreInt32(&n.isLoading, 1)  这样的赋值方式来保证原子性的写入 n.isLoading,为什么不直接赋值呢，比如说 n.isLoading = 1 ,其实是因为这样无法保证原子性，使用StoreInt32赋值的时候，任何cpu都不会进行针对进行同一个值的读或写操作。如果我们把所有针对此值的写操作都改为原子操作，那么就不会出现针对此值的读操作读操作因被并发的进行而读到修改了一半的情况。 相同的。你也应该就能理解为什么它在defer的时候在通过原子性写入，把isLoading 改成0了吧。

接下来nsq读取本地文件 nsqd.dat 里面的内容，作为初始化数据加载进来，循环所有Topic, 初始化所有的Topic,和每一个Topic下面的Channel 。最后启动这个Topic。这一块逻辑比较复杂，后面我们单独开一篇来讲。

继续回到main文件。LoadMetadata后是 PresistMetadata 。从文件中load进来初始化后马上写入到文件一遍。这一步操作应该为了更新 nsqd.dat 文件中的信息,因为在加载的过程中可能会对原有信息做一些改变。比如说版本号等。

最后就是开个子协程执行 Main方法了。这里多说一下，为什么要开个子协程呢？大家可以暂停思考下。其实大家是不是还记得文章一开始的地方说过的nsq是需要第三方进程管理包 go-svc 来托管进程。go-svc在执行完Start方法后，会阻塞监听信号量来判断是否要关闭进程。但是Main方法里面也有业务逻辑要阻塞监听ErrorChannel 来退出进程。所以这里需要2个协程阻塞监听channel. 不知道大家有没有猜到呢？
```go
go func() {
		err := p.nsqd.Main()
		if err != nil {
			//有问题直接停止掉结束进程
			p.Stop()
			os.Exit(1)
		}
	}()
```
下面我们就进入Main函数里面看下他会做什么逻辑，我把不重要的代码删了一些：
```go
func (n *NSQD) Main() error {
    //实例化上下文对下，传入 NSQD 对象作为全局变量
    ctx := &context{n}
    ...
    //waitGroup开个协程 监听tcp连接 一直接受请求 accpet
    n.waitGroup.Wrap(func() {
        exitFunc(protocol.TCPServer(n.tcpListener, n.tcpServer, n.logf))
    })
    //监听http连接 初始化所有的路由 roter
    httpServer := newHTTPServer(ctx, false, n.getOpts().TLSRequired == TLSRequired)
    //开了个协程  监听http
    n.waitGroup.Wrap(func() {
        //调用 http_api.Serve 开始启动 HTTPServer 并在 4151 端口进行 HTTP 通信.
        exitFunc(http_api.Serve(n.httpListener, httpServer, "HTTP", n.logf))
    })
    //循环监控队列信息
    n.waitGroup.Wrap(n.queueScanLoop)    // 处理消息的优先队列
    //开了个协程  节点信息管理
    n.waitGroup.Wrap(n.lookupLoop)      // 如果 nsqd 发生变化，同步至 nsqloopdup，函数定义在 lookup 中
    ...
    //阻塞监听 exitCh  有问题直接返回
    err := <-exitCh
    return err
}
```
nsq 自己实现了一个工具函数 n.waitGroup.Wrap。使用该函数每次会开一个新的协程。 可以看到整个流程下来，阻塞实现http的Accept，阻塞tcp的Accept，（如果有https也会监听https).都是外面包了一个 waitGroup .每个都是一个单独的协程。最后Main函数执行了 n.queueScanLoop 和 n.lookupLoop。这两块都是比较复杂的流程。我们后面会单独开一章来讲。我们可以先简单的了解下。

n.queueScanLoop 函数维护并管理 goroutine 池的数量（默认4个），这些 goroutine 主要用于处理 channel 中 延时优先级队列和等待消费确认优先级队列。同时 queueScanLoop 循环随机选择 channel （默认20个）并交给工作线程池进行处理。

对于等待消费确认的队列，如果超过最大等待时间。nsq将会尝试重新发送消息。

对于延迟消息，每次从最小堆里拿到到底的消息并且发送。

n.lookupLook 函数是用于和lookupd 交户使用的事件处理模块。例如Topic 增加或者删除， channel 增加或者删除 需要对所有 nslookupd 模块做消息广播等处理逻辑，均在此处实现。 主要的事件:

定时心跳操作 每隔 15s 发送 PING 到 所有 nslookupd 的节点上

topic,channel新增删除操作 发送消息到所有 nslookupd 的节点上

配置修改的操作 如果配置修改，会重新从配置中刷新一次 nslookupd 节点

最后，本来打算自己画个启动流程图，不过网上有别人画好的还不错的，我就直接粘过来了。
![流转](https://img1.liangtian.me/myblog/imgs/nsq21.jpg?x-oss-process=style/small)
