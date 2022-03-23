---
title: "nsq 源码 diskQueue 讲解"
date: 2022-03-15T10:15:02+08:00
lastmod: 2022-03-15T10:15:02+08:00
keywords: ["golang","nsq","源码分析"]
description: "diskQueue是backendQueue接口的一个实现。backendQueue的作用是在实现在内存go channel缓冲区满的情况下对消息的处理的对象。 除了diskQueue外还有dummyBackendQueue实现了backendQueue接口。"
tags: ["nsq","源码分析"]
categories: ["golang","源码分析"]
author: "梁天"
---
`diskQueue是backendQueue`接口的一个实现。`backendQueue`的作用是在实现在内存go channel缓冲区满的情况下对消息的处理的对象。 除了diskQueue外还有`dummyBackendQueue`实现了`backendQueue`接口。
<!--more-->
对于临时（#ephemeral结尾）Topic/Channel，在创建时会使用`dummyBackendQueue`初始化backend， `dummyBackendQueue`只是为了统一临时和非临时Topic/Channel而写的，它只是实现了接口，不做任何实质上的操作， 因此在内存缓冲区满时直接丢弃消息。这也是临时Topic/Channel和非临时的一个比较大的差别。 每个非临时Topic/Channel，创建的时候使用`diskQueue`初始化`backend，diskQueue`的功能是将消息写入磁盘进行持久化， 并在需要时从中取出消息重新向客户端投递。

`diskQueue`的实现在nsqd/disk_queue.go中。需要注意一点，查找`diskQueue`中的函数的调用可能不会返回正确的结果， 因为`diskQueue`对外是以`backendQueue`形式存在，因此查找`diskQueue`的函数的调用情况时应当查找`backendQueue`中相应函数的调用。

### 创建和初始化
```go
// New instantiates an instance of diskQueue, retrieving metadata
// from the filesystem and starting the read ahead goroutine
func New(name string, dataPath string, maxBytesPerFile int64,
  minMsgSize int32, maxMsgSize int32,
  syncEvery int64, syncTimeout time.Duration, logf AppLogFunc) Interface {
  d := diskQueue{
    name:              name,
    dataPath:          dataPath,
    maxBytesPerFile:   maxBytesPerFile,
    minMsgSize:        minMsgSize,
    maxMsgSize:        maxMsgSize,
    readChan:          make(chan []byte),
    writeChan:         make(chan []byte),
    writeResponseChan: make(chan error),
    emptyChan:         make(chan int),
    emptyResponseChan: make(chan error),
    exitChan:          make(chan int),
    exitSyncChan:      make(chan int),
    syncEvery:         syncEvery,
    syncTimeout:       syncTimeout,
    logf:              logf,
  }
​
  // no need to lock here, nothing else could possibly be touching this instance
  err := d.retrieveMetaData()
  if err != nil && !os.IsNotExist(err) {
    d.logf(ERROR, "DISKQUEUE(%s) failed to retrieveMetaData - %s", d.name, err)
  }
​
  go d.ioLoop()
  return &d
}
```
`diskQueue`的获得是通过`newDiskQueue`，该函数比较简单，通过传入的参数创建一个`dispQueue`， 然后通过`retrieveMetaData`函数获取之前与该`diskQueue`相关联的`Topic/Channel`已经持久化的信息。最后启动ioLoop循环处理消息。
```go
// retrieveMetaData initializes state from the filesystem
func (d *diskQueue) retrieveMetaData() error {
  var f *os.File
  var err error
​
  fileName := d.metaDataFileName()
  f, err = os.OpenFile(fileName, os.O_RDONLY, 0600)
  if err != nil {
    return err
  }
  defer f.Close()
​
  var depth int64 
   //多少数据，读数量，读指针，写数量，写指针
  _, err = fmt.Fscanf(f, "%d\n%d,%d\n%d,%d\n",
    &depth,
    &d.readFileNum, &d.readPos,
    &d.writeFileNum, &d.writePos)
  if err != nil {
    return err
  }
  atomic.StoreInt64(&d.depth, depth)
  d.nextReadFileNum = d.readFileNum
  d.nextReadPos = d.readPos
​
  return nil
}
```
`retrieveMetaData`函数从磁盘中恢复`diskQueue`的状态。`diskQueue`会定时将自己的状态备份到文件中， 文件名由`metaDataFileName`函数确定。`retrieveMetaData`函数同样通过`metaDataFileName`函数获得保存状态的文件名并打开。 该文件只有三行，格式为`%d\n%d,%d\n%d,%d\n`，第一行保存着该`diskQueue`中消息的数量（depth）， 第二行保存`readFileNum和readPos`，第三行保存`writeFileNum和writePos`。
```go
// persistMetaData atomically writes state to the filesystem
func (d *diskQueue) persistMetaData() error {
  var f *os.File
  var err error
​
  fileName := d.metaDataFileName()
  tmpFileName := fmt.Sprintf("%s.%d.tmp", fileName, rand.Int())
​
  // write to tmp file
  f, err = os.OpenFile(tmpFileName, os.O_RDWR|os.O_CREATE, 0600)
  if err != nil {
    return err
  }
​  //多少数据，读数量，读指针，写数量，写指针 
  _, err = fmt.Fprintf(f, "%d\n%d,%d\n%d,%d\n",
    atomic.LoadInt64(&d.depth),
    d.readFileNum, d.readPos,
    d.writeFileNum, d.writePos)
  if err != nil {
    f.Close()
    return err
  }
  f.Sync()
  f.Close()
​
  // atomically rename
  return os.Rename(tmpFileName, fileName)
}
```
与`retrieveMetaData`相对应的是`persistMetaData`函数，这个函数将运行时的元数据保存到文件用于下次重新构建`diskQueue`时的恢复。 逻辑基本与`retrieveMetaData`，此处不再赘述。

### diskQueue的消息循环
```go
func (d *diskQueue) ioLoop() {
  var dataRead []byte
  var err error
  var count int64
  var r chan []byte
​
  syncTicker := time.NewTicker(d.syncTimeout)
​
  for {
    // dont sync all the time :)
    if count == d.syncEvery {
      d.needSync = true
    }
​
    if d.needSync {
      err = d.sync()
      if err != nil {
        d.logf(ERROR, "DISKQUEUE(%s) failed to sync - %s", d.name, err)
      }
      count = 0
    }
​
    if (d.readFileNum < d.writeFileNum) || (d.readPos < d.writePos) {
      if d.nextReadPos == d.readPos {
        dataRead, err = d.readOne()
        if err != nil {
          d.logf(ERROR, "DISKQUEUE(%s) reading at %d of %s - %s",
            d.name, d.readPos, d.fileName(d.readFileNum), err)
          d.handleReadError()
          continue
        }
      }
      r = d.readChan
    } else {
      r = nil
    }
​
    select {
    // the Go channel spec dictates that nil channel operations (read or write)
    // in a select are skipped, we set r to d.readChan only when there is data to read
    case r <- dataRead:
      count++
      // moveForward sets needSync flag if a file is removed
      d.moveForward()
    case <-d.emptyChan:
      d.emptyResponseChan <- d.deleteAllFiles()
      count = 0
    case dataWrite := <-d.writeChan:
      count++
      d.writeResponseChan <- d.writeOne(dataWrite)
    case <-syncTicker.C:
      if count == 0 {
        // avoid sync when there's no activity
        continue
      }
      d.needSync = true
    case <-d.exitChan:
      goto exit
    }
  }
​
exit:
  d.logf(INFO, "DISKQUEUE(%s): closing ... ioLoop", d.name)
  syncTicker.Stop()
  d.exitSyncChan <- 1
}
```
`ioLoop`函数实现了`diskQueue`的消息循环，`diskQueue`的定时操作和读写操作的核心都在这个函数中完成。

函数首先使用`time.NewTicker(d.syncTimeout)`定义了`syncTicker`变量，`syncTicker`的类型是`time.Ticker`， 每隔`d.syncTimeout`时间就会在`syncTicker.C`这个go channel产生一个消息。 通过`select syncTicker.C`能实现至多`d.syncTimeout`时间就跳出select块一次，这种方式相当于一个延时的default子句。 在ioLoop中，通过这种方式，就能在一个goroutine中既实现消息的接收又实现定时任务（跳出select后执行定时任务，然后在进入select）。 有点类似于定时的轮询。

`ioLoop`的定时任务是调用sync函数刷新文件，防止突然结束程序后内存中的内容未被提交到磁盘，导致内容丢失。 控制是否需要同步的变量是`d.needSync`，该变量在一次sync后会被置为false，在许多需要刷新文件的地方会被置为true。 在ioLoop中，d.needSync变量还跟刷新计数器count变量有关，count值的变化规则如下：

1. 如果一次消息循环中，有写入操作，那么count就会被自增。

2. 当count达到d.syncEvery时，会将count重置为0并且将`d.needSync`置为true，随后进行文件的刷新。

3. 在`emptyChan`收到消息时，count会被重置为0，因为文件已经被删除了，所有要重置刷新计数器。

4. 在`syncTicker.C`收到消息后，会将count重置为0，并且将d.needSync置为true。也就是至多d.syncTimeout时间刷新一次文件。

`ioLoop`还定时检测当前是否有数据需要被读取，如果`(d.readFileNum < d.writeFileNum) || (d.readPos < d.writePos) `和`d.nextReadPos == d.readPos`这两个条件成立，则执行`d.readOne()`并将结果放入`dataRead`中，然后设置`r`为`d.readChan`。 如果条件不成立，则将r置为空值nil。随后的select语句中有case r <- `dataRead:`这样一个分支，在注释中作者写了这是一个Golang的特性， 即：如果r不为空，则会将`dataRead`送入go channel。进入d.readChan的消息通过ReadChan函数向外暴露，最终被Topic/Channel的消息循环读取。 而如果r为空，则这个分支会被跳过。这个特性的使用统一了select的逻辑，简化了当数据为空时的判断。

### diskQueue的写操作
```go
// Put writes a []byte to the queue
func (d *diskQueue) Put(data []byte) error {
    d.RLock()
    defer d.RUnlock()
​
    if d.exitFlag == 1 {
        return errors.New("exiting")
    }
​
    d.writeChan <- data
    return <-d.writeResponseChan
}
```
写操作的对外接口是Put函数，该函数比较简单，加锁，并且将数据放入`d.writeChan`，等待`d.writeResponseChan`的结果后返回。 `d.writeChan`的接收在`ioLoop`中`select`的一个分支，处理时调用`writeOne`函数，并将处理结果放入`d.writeResponseChan`。
```go
// writeOne performs a low level filesystem write for a single []byte
// while advancing write positions and rolling files, if necessary
func (d *diskQueue) writeOne(data []byte) error {
    var err error
​
    if d.writeFile == nil {
        curFileName := d.fileName(d.writeFileNum)
        d.writeFile, err = os.OpenFile(curFileName, os.O_RDWR|os.O_CREATE, 0600)
        if err != nil {
            return err
        }
​
        d.logf("DISKQUEUE(%s): writeOne() opened %s", d.name, curFileName)
​
        if d.writePos > 0 {
            _, err = d.writeFile.Seek(d.writePos, 0)
            if err != nil {
                d.writeFile.Close()
                d.writeFile = nil
                return err
            }
        }
    }
​
    dataLen := int32(len(data))
​
    if dataLen < d.minMsgSize || dataLen > d.maxMsgSize {
        return fmt.Errorf("invalid message write size (%d) maxMsgSize=%d", dataLen, d.maxMsgSize)
    }
​
    d.writeBuf.Reset()
    //先在d里写入4个字节，标记长度 4个字节转成二进制
    err = binary.Write(&d.writeBuf, binary.BigEndian, dataLen)
    if err != nil {
        return err
    }
​    //再往d里写入数据
    _, err = d.writeBuf.Write(data)
    if err != nil {
        return err
    }
​
    // only write to the file once
   // 最终 长度 + 数据 一起写入文件
    _, err = d.writeFile.Write(d.writeBuf.Bytes())
    if err != nil {
        d.writeFile.Close()
        d.writeFile = nil
        return err
    }
​
    totalBytes := int64(4 + dataLen)
    d.writePos += totalBytes
    atomic.AddInt64(&d.depth, 1)
​
    if d.writePos > d.maxBytesPerFile {
        d.writeFileNum++
        d.writePos = 0
​
        // sync every time we start writing to a new file
        err = d.sync()
        if err != nil {
            d.logf("ERROR: diskqueue(%s) failed to sync - %s", d.name, err)
        }
​
        if d.writeFile != nil {
            d.writeFile.Close()
            d.writeFile = nil
        }
    }
​
    return err
}
```

`writeOne`函数是写操作的最终执行部分，负责将消息写入磁盘。函数逻辑比较简单。消息写入步骤如下：

1. 若当前要写的文件不存在，则通过d.fileName(d.writeFileNum)获得文件名，并创建文件

2. 根据d.writePos定位本次写的位置

3. 从要写入的内容得到要写入的长度

4. 先写入3中计算出的消息长度（4字节），然后写入消息本身

5. 将d.writePos后移4 + 消息长度作为下次写入位置。加4是因为消息长度本身也占4字节。

6. 判断d.writePos是否大于每个文件的最大字节数d.maxBytesPerFile，如果是，则将d.writeFileNum加1， 并重置d.writePos。这个操作的目的是为了防止单个文件过大。

7. 如果下次要写入新的文件，那么需要调用sync函数对当前文件进行同步。

### diskQueue的读操作
```go
// readOne performs a low level filesystem read for a single []byte
// while advancing read positions and rolling files, if necessary
func (d *diskQueue) readOne() ([]byte, error) {
    var err error
    var msgSize int32
​
    if d.readFile == nil {
        curFileName := d.fileName(d.readFileNum)
        d.readFile, err = os.OpenFile(curFileName, os.O_RDONLY, 0600)
        if err != nil {
            return nil, err
        }
​
        d.logf("DISKQUEUE(%s): readOne() opened %s", d.name, curFileName)
​
        if d.readPos > 0 {
            _, err = d.readFile.Seek(d.readPos, 0)
            if err != nil {
                d.readFile.Close()
                d.readFile = nil
                return nil, err
            }
        }
​
        d.reader = bufio.NewReader(d.readFile)
    }
​    //先读4个字节 int32
    err = binary.Read(d.reader, binary.BigEndian, &msgSize)
    if err != nil {
        d.readFile.Close()
        d.readFile = nil
        return nil, err
    }
​
    if msgSize < d.minMsgSize || msgSize > d.maxMsgSize {
        // this file is corrupt and we have no reasonable guarantee on
        // where a new message should begin
        d.readFile.Close()
        d.readFile = nil
        return nil, fmt.Errorf("invalid message read size (%d)", msgSize)
    }
​    //得到刚才读到的长度，申请一个固定长度的[]byte数组，比如说长度122
    readBuf := make([]byte, msgSize)   
    //一次性全部读完
    _, err = io.ReadFull(d.reader, readBuf)
    if err != nil {
        d.readFile.Close()
        d.readFile = nil
        return nil, err
    }
​
    totalBytes := int64(4 + msgSize)
​
    // we only advance next* because we have not yet sent this to consumers
    // (where readFileNum, readPos will actually be advanced)
    d.nextReadPos = d.readPos + totalBytes
    d.nextReadFileNum = d.readFileNum
​
    // TODO: each data file should embed the maxBytesPerFile
    // as the first 8 bytes (at creation time) ensuring that
    // the value can change without affecting runtime
    if d.nextReadPos > d.maxBytesPerFile {
        if d.readFile != nil {
            d.readFile.Close()
            d.readFile = nil
        }
​
        d.nextReadFileNum++
        d.nextReadPos = 0
    }
​
    return readBuf, nil
}
​
```
消息读取对外暴露的是一个go channel，而数据的最终来源是ioLoop中调用的readOne函数。readOne函数逻辑跟writeOne类似， 只是把写操作换成了读操作，唯一差异较大的地方是`d.nextReadPos`和`d.nextReadFileNum`这两个变量的使用。

在写操作时，如果写入成功，则可以直接将写入位置和写入文件更新。但是对于读操作来说，由于读取的目的是为了向客户端投递， 因此无法保证一定能投递成功。因此需要使用next开头的两个变量来保存成功后需要读的位置，如果投递没有成功， 则继续使用当前的读取位置将再一次尝试将消息投递给客户端。

```go
func (d *diskQueue) moveForward() {
    oldReadFileNum := d.readFileNum
    d.readFileNum = d.nextReadFileNum
    d.readPos = d.nextReadPos
    depth := atomic.AddInt64(&d.depth, -1)
​
    // see if we need to clean up the old file
    if oldReadFileNum != d.nextReadFileNum {
        // sync every time we start reading from a new file
        d.needSync = true
​
        fn := d.fileName(oldReadFileNum)
        err := os.Remove(fn)
        if err != nil {
            d.logf("ERROR: failed to Remove(%s) - %s", fn, err)
        }
    }
​
    d.checkTailCorruption(depth)
}
```
当消息投递成功后，则使用`moveForward`函数将保存在`d.nextReadPos`和`d.nextReadFileNum`中的值取出， 赋值给`d.readPos`和`d.readFileNum`，`moveForward`函数还负责清理已经读完的旧文件。最后，调用`checkTailCorruption`函数检查文件是否有错， 如果出现错误，则调用`skipToNextRWFile`重置读取和写入的文件编号和位置。

### diskQueue的其他函数

diskQueue中还有与错误处理相关的`handleReadError`，与关闭diskQueue相关的`Close`，`Delete`，`exit`，`Empty`和`deleteAllFiles`等， 函数，逻辑较简单，不再专门分析。

### diskQueue总结
diskQueue主要逻辑是对磁盘的读写操作，较为琐碎但没有复杂的架构。 其中消息循环的思路和读写过程周全的考虑都值得学习的。



