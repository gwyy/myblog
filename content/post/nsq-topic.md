---
title: "nsq Topic"
date: 2022-03-14T20:15:02+08:00
lastmod: 2022-03-14T20:15:02+08:00
keywords: ["golang","nsq","源码分析"]
description: "本篇文章就是由大到小。对于topic这一部分进行详尽的讲解。"
tags: ["nsq","源码分析"]
categories: ["golang","源码分析"]
author: "梁天"
---
与Topic相关的代码主要位于nsqd/topic.go中。

上一篇文字我们讲解了下nsq的启动流程。对nsq的整体框架有了一个大概的了解。本篇文章就是由大到小。对于topic这一部分进行详尽的讲解。
<!--more-->
topic 管理着多个 channel 通过从 client 中获取消息，然后将消息发送到 channel 中传递给客户端.在 channel 初始化时会加载原有的 topic 并在最后统一执行 topic.Start(),新创建的 topic 会同步给 lookupd 后开始运行. nsqd 中通过创建创建多个 topic 来管理不同类别的频道.

### topic结构体：
```go
type Topic struct {
  // 64bit atomic vars need to be first for proper alignment on 32bit platforms
  // 这两个字段仅作统计信息,保证 32 位对其操作
  messageCount uint64  // 累计消息数
  messageBytes uint64// 累计消息体的字节数

  sync.RWMutex  // 加锁，包括 putMessage

  name              string // topic名，生产和消费时需要指定此名称
  channelMap        map[string]*Channel  // 保存每个channel name和channel指针的映射
  backend           BackendQueue    // 磁盘队列，当内存memoryMsgChan满时，写入硬盘队列
  memoryMsgChan     chan *Message    // 消息优先存入这个内存chan
  startChan         chan int    // 接收开始信号的 channel，调用 start 开始 topic 消息循环

  exitChan          chan int    // 判断 topic 是否退出

  // 在 select 的地方都要添加 exitChan
  // 除非使用 default 或者保证程序不会永远阻塞在 select 处,即可以退出循环
  // channel 更新时用来通知并更新消息循环中的 chan 数组
  channelUpdateChan chan int
  // 用来等待所有的子 goroutine
  waitGroup         util.WaitGroupWrapper
  exitFlag          int32     // topic 退出标识符
  idFactory         *guidFactory    // 生成 guid 的工厂方法

  ephemeral      bool  // 该 topic 是否是临时 topic
  deleteCallback func(*Topic)   // topic 删除时的回调函数
  deleter        sync.Once   // 确保 deleteCallback 仅执行一次

  paused    int32   // topic 是否暂停
  pauseChan chan int   // 改变 topic 暂停/运行状态的通道
  ctx *context  // topic 的上下文
}
```
可以看到。topic 采用了 map + *Channel 来管理所有的channel. 并且也有 memoryMsgChan 和 backend 2个队列。

### 实例化Topic :
下面就是 topic 的创建流程,传入的参数参数包括,topicName,上下文环境,删除回调函数:
```go
func NewTopic(topicName string, ctx *context, deleteCallback func(*Topic)) *Topic {
  t := &Topic{
    name:              topicName, //topic名称
    channelMap:        make(map[string]*Channel),
    memoryMsgChan:     nil,
    startChan:         make(chan int, 1),
    exitChan:          make(chan int),
    channelUpdateChan: make(chan int),
    ctx:               ctx, //上下文指针
    paused:            0,
    pauseChan:         make(chan int),
    deleteCallback:    deleteCallback, //删除callback函数
    // 所有 topic 使用同一个 guidFactory，因为都是用的 nsqd 的 ctx.nsqd.getOpts().ID 为基础生成的
    idFactory:         NewGUIDFactory(ctx.nsqd.getOpts().ID),
  }
  // create mem-queue only if size > 0 (do not use unbuffered chan)
  //  // 根据消息队列生成消息 chan,default size = 10000
  if ctx.nsqd.getOpts().MemQueueSize > 0 {
    // 初始化一个消息队列
    t.memoryMsgChan = make(chan *Message, ctx.nsqd.getOpts().MemQueueSize)
  }
  // 判断这个 topic 是不是暂时的，暂时的 topic 消息仅仅存储在内存中
  // DummyBackendQueue 和 diskqueue 均实现了 backend 接口
  if strings.HasSuffix(topicName, "#ephemeral") {
    // 临时的 topic，设置标志并使用 newDummyBackendQueue 初始化 backend
    t.ephemeral = true
    t.backend = newDummyBackendQueue()   // 实现了 backend 但是并没有逻辑，所有操作仅仅返回 nil
  } else {
    dqLogf := func(level diskqueue.LogLevel, f string, args ...interface{}) {
      opts := ctx.nsqd.getOpts()
      lg.Logf(opts.Logger, opts.LogLevel, lg.LogLevel(level), f, args...)
    }
    // 使用 diskqueue 初始化 backend 队列
    t.backend = diskqueue.New(
      topicName,
      ctx.nsqd.getOpts().DataPath,
      ctx.nsqd.getOpts().MaxBytesPerFile,
      int32(minValidMsgLength),
      int32(ctx.nsqd.getOpts().MaxMsgSize)+minValidMsgLength,
      ctx.nsqd.getOpts().SyncEvery,
      ctx.nsqd.getOpts().SyncTimeout,
      dqLogf,
    )
  }
  // 使用一个新的协程来执行 messagePump
  //startChan 就发送给了它,messagePump 函数负责分发整个 topic 接收到的消息给该 topic 下的 channels.
  t.waitGroup.Wrap(t.messagePump)
  // 调用 Notify
  t.ctx.nsqd.Notify(t)

  return t
}
```
可以看到先实例化了一个Topic指针对象。初始化`memoryMsgChan队列`， 默认1000个。并且判断topicName是否是临时topic,如果是的话，`BackendQueue`（这是个接口）实现了一个空的内存Queue. 否则使用 `diskqueue`来初始化 backend队列。

随后，NewTopic函数开启一个新的goroutine来执行messagePump函数，该函数负责消息循环，将进入topic中的消息投递到channel中。

最后，NewTopic函数执行`t.ctx.nsqd.Notify(t)`，该函数在topic和channel创建、停止的时候调用， Notify函数通过执行`PersistMetadata`函数，将topic和channel的信息写到文件中。
```go
func (n *NSQD) Notify(v interface{}) {
  persist := atomic.LoadInt32(&n.isLoading) == 0
  n.waitGroup.Wrap(func() {
    // by selecting on exitChan we guarantee that
    // we do not block exit, see issue #123
    select {
    //如果执行那一刻 有exitChan 那么就走exit
    case <-n.exitChan:
      //否则就走正常逻辑 往notifyChan 里发个消息
    case n.notifyChan <- v:
      if !persist {
        return
      }
      n.Lock()
      err := n.PersistMetadata()
      if err != nil {
        n.logf(LOG_ERROR, "failed to persist metadata - %s", err)
      }
      n.Unlock()
    }
  })
}
```
在`Notify`函数的实现时，首先考虑了数据持久化的时机，如果当前nsqd尚在初始化，则不需要立即持久化数据，因为nsqd在初始化后会进行一次统一的持久化工作，

`Notify`在进行数据持久化的时候采用了异步的方式。使得topic和channel能以同步的方式来调用Nofity而不阻塞。在异步运行的过程中， 通过waitGroup和监听exitChan的使用保证了结束程序时goroutine能正常退出。

在执行持久化之前，`case n.notifyChan <- v:`语句向notifyChan传递消息，触发`lookupLoop`函数（nsqd/lookup.go中）接收`notifyChan`消息的部分， 从而实现向loopupd注册/取消注册响应的topic或channel。

### 消息写入Topic
客户端通过nsqd的HTTP API或TCP API向特定topic发送消息，nsqd的HTTP或TCP模块通过调用对应topic的`PutMessage`或`PutMessages`函数， 将消息投递到topic中。`PutMessage`或`PutMessages`函数都通过topic的私有函数put进行消息的投递，两个函数的区别仅在`PutMessage`只调用一次put， `PutMessages`遍历所有要投递的消息，对每条消息使用put函数进行投递。默认topic会优先往`memoryMsgChan` 队列内投递，如果内存队列已满，才会往磁盘队列写入，（临时的topic磁盘队列不做任何存储，数据直接丢弃）
```go
func (t *Topic) put(m *Message) error {
    select {
    case t.memoryMsgChan <- m:
    default:
        //写入磁盘队列
    }
    return nil
}
```
### Start && messagePump 操作
topic的Start方法就是发送了个 startChan ，这里有个小技巧，nsq使用了select来发送这个消息，这样做的目的是如果start被并发调用了，第二个start会直接走到default里，什么都不做.

那么这个Start函数都有哪里调用的呢。

1. nsqd启动的时候，触发 LoadMetadata     会把文件里的topic加载到内存里，这时候会调用Start方法

2. 用户通过请求获取topic的时候会通过 getTopic 来获取或者创建topic

```go
func (t *Topic) Start() {
  select {
  case t.startChan <- 1:
  default:
  }
}
```
接下来我们看下 `messagePump`, 刚才的 startChan 就是发给了这个函数，该函数在创建新的topic时通过waitGroup在新的goroutine中运行。该函数仅在触发 startChan 开始运行，否则会阻塞住，直到退出。
```go
for {
    select {
    case <-t.channelUpdateChan:
      continue
    case <-t.pauseChan:
      continue
    case <-t.exitChan:
      goto exit
    case <-t.startChan:
    }
    break
  }
```
`messagePump`函数初始化时先获取当前存在的channel数组，设置`memoryMsgChan`和`backendChan`，随后进入消息循环， 在循环中主要处理四种消息：

接收来自`memoryMsgChan`和`backendChan`两个go channel进入的消息，并向当前的channal数组中的channel进行投递

处理当前topic下channel的更新

处理当前topic的暂停和恢复

监听当前topic的删除
### 消息投递
```go
case msg = <-memoryMsgChan:
case buf = <-backendChan:
    msg, err = decodeMessage(buf)
    if err != nil {
        t.ctx.nsqd.logf("ERROR: failed to decode message - %s", err)
        continue
    }
```
这两个case语句处理进入topic的消息，关于两个go channel的区别会在后续的博客中分析。 从`memoryMsgChanbackendChan`读取到的消息是*Message类型，而从`backendChan`读取到的消息是byte数组的。 因此取出`backendChan`的消息后海需要调用`decodeMessage`函数对byte数组进行解码，返回*Message类型的消息。 二者都保存在msg变量中。
```go
for i, channel := range chans {
    chanMsg := msg
    if i > 0 {
        chanMsg = NewMessage(msg.ID, msg.Body)
        chanMsg.Timestamp = msg.Timestamp
        chanMsg.deferred = msg.deferred
    }
    if chanMsg.deferred != 0 {
        channel.StartDeferredTimeout(chanMsg, chanMsg.deferred)
        continue
    }
    err := channel.PutMessage(chanMsg)
    if err != nil {
        t.ctx.nsqd.logf(
            "TOPIC(%s) ERROR: failed to put msg(%s) to channel(%s) - %s",
            t.name, msg.ID, channel.name, err)
    }
}
```
随后是将消息投到每个channel中，首先先对消息进行复制操作，这里有个优化，对于第一次循环， 直接使用原消息进行发送以减少复制对象的开销，此后的循环将对消息进行复制。对于即时的消息， 直接调用channel的PutMessage函数进行投递，对于延迟的消息， 调用channel的`StartDeferredTimeout`函数进行投递。对于这两个函数的投递细节，后续博文中会详细分析。

### Topic下Channel的更新
```go
case <-t.channelUpdateChan:
    chans = chans[:0]
    t.RLock()
    for _, c := range t.channelMap {
        chans = append(chans, c)
    }
    t.RUnlock()
    if len(chans) == 0 || t.IsPaused() {
        memoryMsgChan = nil
        backendChan = nil
    } else {
        memoryMsgChan = t.memoryMsgChan
        backendChan = t.backend.ReadChan()
    }
    continue
```
Channel的更新比较简单，从`channelMap`中取出每个channel，构成channel的数组以便后续进行消息的投递。 并且根据当前是否有channel以及该topic是否处于暂停状态来决定`memoryMsgChan和backendChan`是否为空。

### Topic的暂停和恢复
```go
case pause := <-t.pauseChan:
    if pause || len(chans) == 0 {
        memoryMsgChan = nil
        backendChan = nil
    } else {
        memoryMsgChan = t.memoryMsgChan
        backendChan = t.backend.ReadChan()
    }
    continue
```
这个case既处理topic的暂停也处理topic的恢复，pause变量决定其究竟是哪一种操作。 Topic的暂停和恢复其实和topic的更新很像，根据是否暂停以及是否有channel来决定是否分配memoryMsgChan和backendChan。

### messagePump函数的退出
```go
case <-t.exitChan:
    goto exit

// ...
exit:
    t.ctx.nsqd.logf("TOPIC(%s): closing ... messagePump", t.name)
}
// End of messagePump
```
`messagePump`通过监听exitChan来获知topic是否被删除，当topic的删除时，跳转到函数的最后，输出日志后退出消息循环。

### Topic的关闭和删除
```go
// Delete empties the topic and all its channels and closes
func (t *Topic) Delete() error {
    return t.exit(true)
}

// Close persists all outstanding topic data and closes all its channels
func (t *Topic) Close() error {
    return t.exit(false)
}

func (t *Topic) exit(deleted bool) error {
    if !atomic.CompareAndSwapInt32(&t.exitFlag, 0, 1) {
        return errors.New("exiting")
    }

    if deleted {
        t.ctx.nsqd.logf("TOPIC(%s): deleting", t.name)

        // since we are explicitly deleting a topic (not just at system exit time)
        // de-register this from the lookupd
        t.ctx.nsqd.Notify(t)
    } else {
        t.ctx.nsqd.logf("TOPIC(%s): closing", t.name)
    }

    close(t.exitChan)

    // synchronize the close of messagePump()
    t.waitGroup.Wait()

    if deleted {
        t.Lock()
        for _, channel := range t.channelMap {
            delete(t.channelMap, channel.name)
            channel.Delete()
        }
        t.Unlock()

        // empty the queue (deletes the backend files, too)
        t.Empty()
        return t.backend.Delete()
    }

    // close all the channels
    for _, channel := range t.channelMap {
        err := channel.Close()
        if err != nil {
            // we need to continue regardless of error to close all the channels
            t.ctx.nsqd.logf("ERROR: channel(%s) close - %s", channel.name, err)
        }
    }

    // write anything leftover to disk
    t.flush()
    return t.backend.Close()
}
// Exiting returns a boolean indicating if this topic is closed/exiting
func (t *Topic) Exiting() bool {
    return atomic.LoadInt32(&t.exitFlag) == 1
}
```
Topic关闭和删除的实现都是调用exit函数，只是传递的参数不同，删除时调用exit(true)，关闭时调用exit(false)。 exit函数进入时通过`atomic.CompareAndSwapInt32`函数判断当前是否正在退出，如果不是，则设置退出标记，对于已经在退出的topic，不再重复执行退出函数。 接着对于关闭操作，使用Notify函数通知lookupd以便其他nsqd获知该消息。

随后，exit函数调用`close(t.exitChan)`和`t.waitGroup.Wait()`通知其他正在运行goroutine当前topic已经停止，并等待`waitGroup`中的goroutine结束运行。

最后，对于删除和关闭两种操作，执行不同的逻辑来完成最后的清理工作：

1. 对于删除操作，需要清空`channelMap`并删除所有channel，然后删除内存和磁盘中所有未投递的消息。最后关闭backend管理的的磁盘文件。

2. 对于关闭操作，不清空channelMap，只是关闭所有的channel，使用flush函数将所有`memoryMsgChan`中未投递的消息用`writeMessageToBackend`保存到磁盘中。最后关闭backend管理的的磁盘文件。

```go
func (t *Topic) flush() error {
    //...
    for {
        select {
        case msg := <-t.memoryMsgChan:
            err := writeMessageToBackend(&msgBuf, msg, t.backend)
            if err != nil {
                t.ctx.nsqd.logf(
                    "ERROR: failed to write message to backend - %s", err)
            }
        default:
            goto finish
        }
    }
    
finish:
    return nil
}
```
`flush`函数也使用到了default分支来检测是否已经处理完全部消息。 由于此时已经没有生产者向memoryMsgChan提供消息，因此如果出现阻塞就表示消息已经处理完毕。

```go
func (t *Topic) Empty() error {
    for {
        select {
        case <-t.memoryMsgChan:
        default:
            goto finish
        }
    }
​
finish:
    return t.backend.Empty()
}
```
在删除topic时用到的`Empty`函数跟`flush`处理逻辑类似，只不过Empty只释放`memoryMsgChan`消息，而不保存它们。

topic 下的源码基本就看完了，虽然还没有别的部分完整的完整的串联起来，但是也可以了解到，多个 topic 在初始化时就开启了消息循环 goroutine，执行完 Start 后开始消息分发，如果是正常的Topic,除了默认10000的内存队列，还会有个硬盘队列。topic将收到的消息分发到管理的 channel 中.每个 topic 运行的 goroutine 比较简单，只有一个消息分发 `goroutine: messagePump`