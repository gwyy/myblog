---
title: "nsq - 一条消息的生命周期（一)"
date: 2022-03-15T13:15:02+08:00
lastmod: 2022-03-15T13:15:02+08:00
keywords: ["golang","nsq","源码分析"]
description: "nsq - 一条消息的生命周期（一)"
tags: ["golang","nsq","源码分析"]
categories: ["golang","源码分析"]
author: "梁天"
---
本篇我们带着大家一起走完一遍nsq的生命周期。
<!--more-->

经过前面几篇的学习，相信大家对nsq已经有了一个大概的了解，我在写这篇文章的时候也看了很多其他人写的教程，发现大家对于分析系统每个点写的很不错，但是都很少有整体串起来一起走一遍，所以，我打算分成2-3章来带着大家从nsq启动到创建一个topic,然后发一条消息，最后再开个消费者接收消息，中间的所有流程都带大家一起走一遍，从而让大家能够深入地理解nsq的整体运行机制。

今天，这篇文章是整个 《一条消息的生命周期》第一章，我会从nsq的启动，nsqlookupd连接等方面开始讲起。

### 启动nsq
相信看了nsq这个系列的童鞋应该都知道nsq的启动脚本在哪里了吧，没错。就是在`apps/nsqd/main.go` 文件。我们可以切到当前目录，不过在这之前我们要先启动位于 `apps/nsqlookupd/`目录下的 `nsqlookupd`
```go
#启动 nsqlookupd
输出--------------------------------------------------------
➜  nsqlookupd git:(master) ✗ go run main.go 
[nsqlookupd] 2021/10/13 15:27:57.828505 INFO: nsqlookupd v1.2.1-alpha (built w/go1.15.15)
[nsqlookupd] 2021/10/13 15:27:57.828996 INFO: TCP: listening on [::]:4160
[nsqlookupd] 2021/10/13 15:27:57.828996 INFO: HTTP: listening on [::]:4161
[nsqlookupd] 2021/10/13 15:31:20.121567 INFO: TCP: new client(127.0.0.1:54011)
[nsqlookupd] 2021/10/13 15:31:20.121852 INFO: CLIENT(127.0.0.1:54011): desired protocol magic '  V1'
[nsqlookupd] 2021/10/13 15:31:20.122590 INFO: CLIENT(127.0.0.1:54011): IDENTIFY Address:liangtiandeMacBook-Pro.local TCP:4150 HTTP:4151 Version:1.2.1-alpha
[nsqlookupd] 2021/10/13 15:31:20.122661 INFO: DB: client(127.0.0.1:54011) REGISTER category:client key: subkey:
[nsqlookupd] 2021/10/13 15:31:35.121527 INFO: CLIENT(127.0.0.1:54011): pinged (last ping 14.998981s)
[nsqlookupd] 2021/10/13 15:31:50.120787 INFO: CLIENT(127.0.0.1:54011): pinged (last ping 14.99928s)
​
​
#接着我们启动nsq 
go run main.go options.go  --lookupd-tcp-address=127.0.0.1:4160
输出------------------------------------------------------------------------
[nsqd] 2021/10/13 15:31:20.095882 INFO: nsqd v1.2.1-alpha (built w/go1.15.15)
[nsqd] 2021/10/13 15:31:20.096040 INFO: ID: 933
[nsqd] 2021/10/13 15:31:20.096421 INFO: NSQ: persisting topic/channel metadata to nsqd.dat
[nsqd] 2021/10/13 15:31:20.120544 INFO: TCP: listening on [::]:4150
[nsqd] 2021/10/13 15:31:20.120655 INFO: LOOKUP(127.0.0.1:4160): adding peer
[nsqd] 2021/10/13 15:31:20.120685 INFO: LOOKUP connecting to 127.0.0.1:4160
[nsqd] 2021/10/13 15:31:20.120686 INFO: HTTP: listening on [::]:4151
[nsqd] 2021/10/13 15:31:20.123026 INFO: LOOKUPD(127.0.0.1:4160): peer info {TCPPort:4160 HTTPPort:4161 Version:1.2.1-alpha BroadcastAddress:liangtiandeMacBook-Pro.local}
```
可以看到，会输出默认的TCP和HTTP监听的端口，并且会把数据文件写入到当前目录的 nsqd.dat 内。并且连上了nsqlookupd 这个时候我们就算启动了nsqd。

### nsq和nsqlookupd 的链接
虽然启动成功了，但是我们还不知道nsq是怎么和nsqlookup链接上的，并且定期心跳的。其实nsqd主函数Main中启动与nsqlookupd服务通讯的工作线程lookupLoop
```go
ticker := time.Tick(15 * time.Second)
  for {
    if connect {
      //循环所有的 nsqlookupd 地址 我们这边就一个 127.0.0.1:4160
      for _, host := range n.getOpts().NSQLookupdTCPAddresses {
        if in(host, lookupAddrs) {
          continue
        }
        //LOOKUP(127.0.0.1:4160): adding peer
        n.logf(LOG_INFO, "LOOKUP(%s): adding peer", host)
        //实例化newLookupPeer数据结构，并且拿到链接callback方法
        lookupPeer := newLookupPeer(host, n.getOpts().MaxBodySize, n.logf,
          connectCallback(n, hostname))
        //尝试链接
        lookupPeer.Command(nil) // start the connection
        //把nsqlookupd 写入lookupPeers
        lookupPeers = append(lookupPeers, lookupPeer)
        lookupAddrs = append(lookupAddrs, host)
      }
      n.lookupPeers.Store(lookupPeers)
      connect = false
    }
​
```
第一次循环的时候，变量connect = true，nsq会尝试链接n`sqlookupd`. 其实就是连接上nsqlookupd的tcp端口，并且发送 V1信息。
```go
//标记链接成功
lp.state = stateConnected
//发送  V1
_, err = lp.Write(nsq.MagicV1)
```
发送后 V1后，如果没有失败，紧接着nsq会执行connectCallback，在connectCallback里面我们可以看下代码：

```go
func connectCallback(n *NSQD, hostname string) func(*lookupPeer) {
  return func(lp *lookupPeer) {
    //鉴权
    ci := make(map[string]interface{})
    ci["version"] = version.Binary
    ci["tcp_port"] = n.RealTCPAddr().Port
    ci["http_port"] = n.RealHTTPAddr().Port
    ci["hostname"] = hostname
    ci["broadcast_address"] = n.getOpts().BroadcastAddress
​
    cmd, err := nsq.Identify(ci)
    if err != nil {
      lp.Close()
      return
    }
    //发送鉴权
    resp, err := lp.Command(cmd)
    if err != nil {
      n.logf(LOG_ERROR, "LOOKUPD(%s): %s - %s", lp, cmd, err)
      return
    } else if bytes.Equal(resp, []byte("E_INVALID")) {
      n.logf(LOG_INFO, "LOOKUPD(%s): lookupd returned %s", lp, resp)
      lp.Close()
      return
    } else {
      err = json.Unmarshal(resp, &lp.Info)
      if err != nil {
        n.logf(LOG_ERROR, "LOOKUPD(%s): parsing response - %s", lp, resp)
        lp.Close()
        return
      } else {
        //鉴权成功
        // LOOKUPD(127.0.0.1:4160): peer info {TCPPort:4160 HTTPPort:4161 Version:1.2.1-alpha BroadcastAddress:liangtiandeMacBook-Pro.local}
        n.logf(LOG_INFO, "LOOKUPD(%s): peer info %+v", lp, lp.Info)
        if lp.Info.BroadcastAddress == "" {
          n.logf(LOG_ERROR, "LOOKUPD(%s): no broadcast address", lp)
        }
      }
    }
​
    // build all the commands first so we exit the lock(s) as fast as possible
    var commands []*nsq.Command
    n.RLock()
    for _, topic := range n.topicMap {
      topic.RLock()
      if len(topic.channelMap) == 0 {
        commands = append(commands, nsq.Register(topic.name, ""))
      } else {
        for _, channel := range topic.channelMap {
          commands = append(commands, nsq.Register(channel.topicName, channel.name))
        }
      }
      topic.RUnlock()
    }
    n.RUnlock()
    for _, cmd := range commands {
      n.logf(LOG_INFO, "LOOKUPD(%s): %s", lp, cmd)
      _, err := lp.Command(cmd)
      if err != nil {
        n.logf(LOG_ERROR, "LOOKUPD(%s): %s - %s", lp, cmd, err)
        return
      }
    }
  }
}
```
`connectCallback`函数没有任何逻辑，直接return了一个匿名函数，该匿名函数里首先会组装一个map,把自己的信息写入到内，包括版本，tcp端口，http端口，hostname, 主机名等包装到一个结构体内发送。当`nsqlookupd`接收到信息后，其实不会做任何校验，只是单纯的拿到数据后放入到`nsqlookupd`的全局DB-map中的client内。
```go
// body is a json structure with producer information
  peerInfo := PeerInfo{id: client.RemoteAddr().String()}
  //unmarshal 成功就表示注册成功
  err = json.Unmarshal(body, &peerInfo)
  if err != nil {
    return nil, protocol.NewFatalClientErr(err, "E_BAD_BODY", "IDENTIFY failed to decode JSON body")
  }
​
  peerInfo.RemoteAddress = client.RemoteAddr().String()
​
  // require all fields
  if peerInfo.BroadcastAddress == "" || peerInfo.TCPPort == 0 || peerInfo.HTTPPort == 0 || peerInfo.Version == "" {
    return nil, protocol.NewFatalClientErr(nil, "E_BAD_BODY", "IDENTIFY missing fields")
  }
​
  atomic.StoreInt64(&peerInfo.lastUpdate, time.Now().UnixNano())
​
  p.ctx.nsqlookupd.logf(LOG_INFO, "CLIENT(%s): IDENTIFY Address:%s TCP:%d HTTP:%d Version:%s",
    client, peerInfo.BroadcastAddress, peerInfo.TCPPort, peerInfo.HTTPPort, peerInfo.Version)
​
  //写入到 client DB里
  client.peerInfo = &peerInfo
  if p.ctx.nsqlookupd.DB.AddProducer(Registration{"client", "", ""}, &Producer{peerInfo: client.peerInfo}) {
    p.ctx.nsqlookupd.logf(LOG_INFO, "DB: client(%s) REGISTER category:%s key:%s subkey:%s", client, "client", "", "")
  }
​
  // build a response  返回response
  data := make(map[string]interface{})
  data["tcp_port"] = p.ctx.nsqlookupd.RealTCPAddr().Port
  data["http_port"] = p.ctx.nsqlookupd.RealHTTPAddr().Port
  data["version"] = version.Binary
  hostname, err := os.Hostname()
  if err != nil {
    log.Fatalf("ERROR: unable to get hostname %s", err)
  }
  data["broadcast_address"] = p.ctx.nsqlookupd.opts.BroadcastAddress
  data["hostname"] = hostname
​
  response, err := json.Marshal(data)
  if err != nil {
    p.ctx.nsqlookupd.logf(LOG_ERROR, "marshaling %v", data)
    return []byte("OK"), nil
  }
  return response, nil
```
鉴权成功后，会触发当前nsq所有的topic和channel注册到`nsqlookupd`内，由于我们是新启动的服务所以这一步直接跳过。紧接着connect变量就会设置成false。表示链接成功了。后面的每次for循环基本上都是触发了15秒的ticker做了一次ping操作。nsq 发送ping 到 nsqlookup后，nsqlookupd做的唯一一步就是把lastUpdate更新掉。其他没做任何操作。

```go
//每次ping后，修改lastUpdate 时间
atomic.StoreInt64(&client.peerInfo.lastUpdate, now.UnixNano())
```
### 客户端创建topic

nsq客户端可以使用官方封装的go-nsq包。
```go
go get -u github.com/nsqio/go-nsq
```
我们简单实现一个发送者程序：
```go
addr := "127.0.0.1:4150"
topic := "first_topic"
channel := "first_channel"
defaultConfig := nsq.NewConfig()
//新建生产者
p, err := nsq.NewProducer(addr, defaultConfig)
if err != nil {
panic(err)
}
//创建一个topic
p.Publish(topic, []byte("Hello Pibigstar"))
```
我们可以看到，先实例化了 NewConfig. 它会获得`nsqclient`的Config对象，并且通过Config结构体的默认配置注入配置。设置Config对象里的`initialized`属性为true. 表示初始化成功。这里有个注意点，nsq的golang客户端中，`consumer`实现了从nsqlookupd中动态拉取服务列表，并进行消费，但是`producer`中没有实现这个。所以发送消息需要填写nsq的地址。

接下来调用`NewProducer`方法 实例化一个 `Producer`对象：
```go
func NewProducer(addr string, config *Config) (*Producer, error) {
  //检查配置文件，是否初始化，验证是否成功
  config.assertInitialized()
  err := config.Validate()
  if err != nil {
    return nil, err
  }
  //实例化Producer
  p := &Producer{
    //id 自增1
    id: atomic.AddInt64(&instCount, 1),
​
    addr:   addr,//nsqlookupd address
    config: *config,  //配置文件
​
    logger: log.New(os.Stderr, "", log.Flags()),
    logLvl: LogLevelInfo,
​
    transactionChan: make(chan *ProducerTransaction),
    exitChan:        make(chan int),
    responseChan:    make(chan []byte),
    errorChan:       make(chan []byte),
  }
  return p, nil
}
```
该函数比较简单，首先检查了下配置是否初始化（initialized）。接着对配置项进行 min/max 范围校验。成功后就直接实例化Producer对象，Producer对象会保存config的引用和nsq 的地址信息。

最后我们看下最核心的函数 Publish 基本上所有的逻辑都是在Publish里面实现的。, Publish函数本身没有内容，它直接调用了 `w.sendCommand(Publish(topic, body))` 我们转到 sendCommand 函数看下：
```go
func (w *Producer) sendCommand(cmd *Command) error {
  //提前设置了一个接受返回参数的Chan, 这里有伏笔，埋伏它一手
  doneChan := make(chan *ProducerTransaction)
  //调用了sendCommandAsync 并且把doneChan 传进去了
  err := w.sendCommandAsync(cmd, doneChan, nil)
  if err != nil {
    close(doneChan)
    return err
  }
  //上面函数结束后，在这里苦苦的等待 doneChan的返回值，所以我们可以大胆的推测 sendCommandAsync 方法并不返回真实的值
  t := <-doneChan
  return t.Error
}
```
这个方法里面大家不要漏了 doneChan , nsq通过这个channel实现了一个高效的ioLoop模型。虽然说`sendCommandAsync`函数名里有个async，但是它并不是同步返回的。而是等待 doneChan这个channel 的返回。并且最后返回内部的Error属性。我们继续看下去。
```go
func (w *Producer) sendCommandAsync(cmd *Command, doneChan chan *ProducerTransaction,
  args []interface{}) error {
  // keep track of how many outstanding producers we're dealing with
  // in order to later ensure that we clean them all up...
  atomic.AddInt32(&w.concurrentProducers, 1)
  defer atomic.AddInt32(&w.concurrentProducers, -1)
  if atomic.LoadInt32(&w.state) != StateConnected {
    err := w.connect()
    if err != nil {
      return err
    }
  }
  t := &ProducerTransaction{
    cmd:      cmd,
    doneChan: doneChan,
    Args:     args,
  }
  select {
  case w.transactionChan <- t:
  case <-w.exitChan:
    return ErrStopped
  }
  return nil
}
```
该函数比较简单，判断是否连接，如果没有连接调用 `connect()` 方法，接着包一个 `ProducerTransaction`结构体。记录要发送的信息和刚才传过来的`doneChan`，发送到 `w.transactionChan`内。到这里发送者代码就全部完了。但是这就全部看完了吗。其实我们只是看了冰山一角。接下里我们要看下 connect() 方法。
```go
func (w *Producer) connect() error {
  ...
  w.conn = NewConn(w.addr, &w.config, &producerConnDelegate{w})
  w.conn.SetLogger(logger, logLvl, fmt.Sprintf("%3d (%%s)", w.id))
​
  _, err := w.conn.Connect()
  atomic.StoreInt32(&w.state, StateConnected)
  w.closeChan = make(chan int)
  w.wg.Add(1)
  go w.router()
  return nil
}
```
NewConn传入配置文件，初始化Conn结构体。调用`w.conn.Connect()` 连接。我们先简单看下 `w.conn.Connect()`方法:
```go
func (c *Conn) Connect() (*IdentifyResponse, error) {
  dialer := &net.Dialer{
    LocalAddr: c.config.LocalAddr,
    Timeout:   c.config.DialTimeout,
  }
  //打开tcp端口
  conn, err := dialer.Dial("tcp", c.addr)
  c.conn = conn.(*net.TCPConn)
  c.r = conn
  c.w = conn
  //发送[]byte("  V2")
  _, err = c.Write(MagicV2)
  //身份校验
  resp, err := c.identify()
  if err != nil {
    return nil, err
  }
​
  if resp != nil && resp.AuthRequired {
    if c.config.AuthSecret == "" {
      c.log(LogLevelError, "Auth Required")
      return nil, errors.New("Auth Required")
    }
    err := c.auth(c.config.AuthSecret)
    if err != nil {
      c.log(LogLevelError, "Auth Failed %s", err)
      return nil, err
    }
  }
​
  c.wg.Add(2)
  atomic.StoreInt32(&c.readLoopRunning, 1)
  go c.readLoop()
  go c.writeLoop()
  return resp, nil
}
```
该方法连接到nsq，并进行身份校验。核心是最后几行代码。开了2个协程。`readLoop()` 和 `writeLoop()` 用来接收消息和写入消息。

这里先停顿下，我们先跳回去继续看producer，当它连接上nsq之后，会开个 go w.router() 协程，我们看下内部实现：
```go
func (w *Producer) router() {
  for {
    select {
    case t := <-w.transactionChan:
      w.transactions = append(w.transactions, t)
      err := w.conn.WriteCommand(t.cmd)
      if err != nil {
        w.log(LogLevelError, "(%s) sending command - %s", w.conn.String(), err)
        w.close()
      }
    case data := <-w.responseChan:
      w.popTransaction(FrameTypeResponse, data)
    case data := <-w.errorChan:
      w.popTransaction(FrameTypeError, data)
    case <-w.closeChan:
      goto exit
    case <-w.exitChan:
      goto exit
    }
  }
​
exit:
  w.transactionCleanup()
  w.wg.Done()
  w.log(LogLevelInfo, "exiting router")
}
```
在这个方法里就是监听多个chan，分别是：是否有需要发送的消息，是否有收到的响应，是否有错误，是否有退出消息。刚才我们包装的 `transactionChan` 就是通过这里发出去了。到这里整个发送流程就已经全部完成了。那么我们怎么知道到底是发送成功还是失败了呢。这个时候就回到了刚才我们看到的在`connect`的时候开的2个协程`readLoop()` 和 `writeLoop()` 了。在这之前我们先了解下nsq的三种消息类型：
```go
frame typesconst (  
  FrameTypeResponse int32 = 0   //响应  
  FrameTypeError    int32 = 1   //错误   
  FrameTypeMessage  int32 = 2   //消息
)
```
然后我们看下readLoop

```go
func (c *Conn) readLoop() {
  delegate := &connMessageDelegate{c}
  for { 
  ...
    frameType, data, err := ReadUnpackedResponse(c)
  ...
    switch frameType {
    case FrameTypeResponse:
      c.delegate.OnResponse(c, data)
    case FrameTypeMessage:
      msg, err := DecodeMessage(data)
      if err != nil {
        c.log(LogLevelError, "IO error - %s", err)
        c.delegate.OnIOError(c, err)
        goto exit
      }
      msg.Delegate = delegate
      msg.NSQDAddress = c.String()
​
      atomic.AddInt64(&c.messagesInFlight, 1)
      atomic.StoreInt64(&c.lastMsgTimestamp, time.Now().UnixNano())
​
      c.delegate.OnMessage(c, msg)
    case FrameTypeError:
      c.log(LogLevelError, "protocol error - %s", data)
      c.delegate.OnError(c, data)
    default:
      c.log(LogLevelError, "IO error - %s", err)
      c.delegate.OnIOError(c, fmt.Errorf("unknown frame type %d", frameType))
    }
  }
​
exit:
...
}
```
readLoop 核心的代码接收到消息后判断消息类型，如果是响应`(FrameTypeResponse)`。调用 `c.delegate.OnResponse(c, data)` ,如果是消息`(FrameTypeMessage)`，那么就增加`messageInFlight` 数，并且更新`lastMsgTimestamp` 时间，最后调用 `c.delegate.OnMessage(c, msg)`。 但是 `c.delegate` 这个接口是哪里实现的呢。我们可以看到 producer 在connect的时候传入过：
```go
w.conn = NewConn(w.addr, &w.config, &producerConnDelegate{w})
```
所以最终就是调用producerConnDelegate结构体的 OnResponse 和OnMessage。 转到producerConnDelegate结构体的方法非常简单：

```go
func (d *producerConnDelegate) OnResponse(c *Conn, data []byte)       { d.w.onConnResponse(c, data) }
func (d *producerConnDelegate) OnError(c *Conn, data []byte)          { d.w.onConnError(c, data) }
func (d *producerConnDelegate) OnMessage(c *Conn, m *Message)         {}
```
它只处理了`OnResponse` 和 onError, 针对`OnMessage`不做任何处理。`OnResponse`也很简单。`d.w.onConnResponse(c, data)` 我们转到 `onConnResponse` 发现也是只有一句代码：

```go
func (w *Producer) onConnResponse(c *Conn, data []byte) { w.responseChan <- data }
```
这里就和之前的 producer的router方法对应上了。router接受 `responseChan`或者 errorChan 执行 `popTransaction `方法。

```go
func (w *Producer) popTransaction(frameType int32, data []byte) {
  t := w.transactions[0]
  w.transactions = w.transactions[1:]
  if frameType == FrameTypeError {
    t.Error = ErrProtocol{string(data)}
  }
  t.finish()
}
```
首先获取第一个transactions中的元素，如果是错误的响应，那么给他的Error上设置错误信息，最后调用finish方法

```go
func (t *ProducerTransaction) finish() {
  if t.doneChan != nil {
    t.doneChan <- t
  }
}
```
这时候发送的就我们刚才创建的doneChan中传入发送结果，那么用户就可以通过doneChan知道消息是否发送成功了。最后我画了一幅简单的图大家可以参考下：

![流转](https://img1.liangtian.me/myblog/imgs/nsq22.png?x-oss-process=style/small)















