---
title: "Golang select的用法"
date: 2020-09-07T11:32:11+08:00
lastmod: 2020-09-07T11:32:11+08:00
keywords: ["golang","golang基础"]
description: "Golang select的用法"
tags: ["golang"]
categories: ["golang"]
author: "梁天"
---
golang的select与channel配合使用。它用于等待一个或者多个channel的输出。本篇我们重点讲下select的用法。
<!--more-->

golang中的select语句格式如下：
```go
select {
    case <-ch1:
        // 如果从 ch1 信道成功接收数据，则执行该分支代码
    case ch2 <- 1:
        // 如果成功向 ch2 信道成功发送数据，则执行该分支代码
    default:
        // 如果上面都没有成功，则进入 default 分支处理流程
}
```
可以看到select的语法结构有点类似于switch，但又有些不同。

select里的case后面并不带判断条件，而是一个信道的操作，不同于switch里的case，对于从其它语言转过来的开发者来说有些需要特别注意的地方。

golang 的 select 就是监听 IO 操作，当 IO 操作发生时，触发相应的动作每个case语句里必须是一个IO操作，确切的说，应该是一个面向channel的IO操作。

> 注：Go 语言的 select 语句借鉴自 Unix 的 select() 函数，在 Unix 中，可以通过调用 select() 函数来监控一系列的文件句柄，一旦其中一个文件句柄发生了 IO 动作，该 select() 调用就会被返回（C 语言中就是这么做的），后来该机制也被用于实现高并发的 Socket 服务器程序。Go 语言直接在语言级别支持 select关键字，用于处理并发编程中通道之间异步 IO 通信问题。

注意：如果 ch1 或者 ch2 信道都阻塞的话，就会立即进入 default 分支，并不会阻塞。但是如果没有 default 语句，则会阻塞直到某个信道操作成功为止。

**知识点**

1. select语句只能用于信道的读写操作
2. select中的case条件(非阻塞)是并发执行的，select会选择先操作成功的那个case条件去执行，如果多个同时返回，则随机选择一个执行，此时将无法保证执行顺序。对于阻塞的case语句会直到其中有信道可以操作，如果有多个信道可操作，会随机选择其中一个 case 执行
3. 对于case条件语句中，如果存在信道值为nil的读写操作，则该分支将被忽略，可以理解为从select语句中删除了这个case语句
4. 如果有超时条件语句，判断逻辑为如果在这个时间段内一直没有满足条件的case,则执行这个超时case。如果此段时间内出现了可操作的case,则直接执行这个case。一般用超时语句代替了default语句
5. 对于空的select{}，会引起死锁
6. 对于for中的select{}, 也有可能会引起cpu占用过高的问题

下面列出每种情况的示例代码

## **1. select语句只能用于信道的读写操作**

```go
package main
 
import "fmt"
 
func main() {
    size := 10
    ch := make(chan int, size)
    for i := 0; i < size; i++ {
        ch <- 1
    }
 
    ch2 := make(chan int, size)
    for i := 0; i < size; i++ {
        ch2 <- 2
    }
 
    ch3 := make(chan int, 1)
 
    select {
    case 3 == 3:
        fmt.Println("equal")
    case v := <-ch:
        fmt.Print(v)
    case b := <-ch2:
        fmt.Print(b)
    case ch3 <- 10:
        fmt.Print("write")
    default:
        fmt.Println("none")
    }
}
语句会报错
 
prog.go:20:9: 3 == 3 evaluated but not used
prog.go:20:9: select case must be receive, send or assign recv<br>从错误信息里我们证实了第一点。
```
## **2. select中的case语句是随机执行的**

```go
package main
 
import "fmt"
 
func main() {
    size := 10
    ch := make(chan int, size)
    for i := 0; i < size; i++ {
        ch <- 1
    }
 
    ch2 := make(chan int, size)
    for i := 0; i < size; i++ {
        ch2 <- 2
    }
 
    ch3 := make(chan int, 1)
 
    select {
    case v := <-ch:
        fmt.Print(v)
    case b := <-ch2:
        fmt.Print(b)
    case ch3 <- 10:
        fmt.Print("write")
    default:
        fmt.Println("none")
    }
}
```
多次执行的话，会随机输出不同的值，分别为1,2,write。这是因为ch和ch2是并发执行会同时返回数据，所以会随机选择一个case执行，。但永远不会执行default语句，因为上面的三个case都是可以操作的信道。



## **3. 对于case条件语句中，如果存在通道值为nil的读写操作，则该分支将被忽略**

```go
package main
 
import "fmt"
 
func main() {
    var ch chan int
    // ch = make(chan int)
     
    go func(c chan int) {
        c <- 100
    }(ch)
 
    select {
    case <-ch:
        fmt.Print("ok")
 
    }
}
报错
 
fatal error: all goroutines are asleep - deadlock!
 
goroutine 1 [select (no cases)]:
main.main()
    /tmp/sandbox488456896/main.go:14 +0x60
 
goroutine 5 [chan send (nil chan)]:
main.main.func1(0x0, 0x1043a070)
    /tmp/sandbox488456896/main.go:10 +0x40
created by main.main
    /tmp/sandbox488456896/main.go:9 +0x40
可以看到 “goroutine 1 [select (no cases)]” ，虽然写了case条件，但操作的是nil通道，被优化掉了。
要解决这个问题，只能使用make()进行初始化才可以。
```

## **4. 超时用法**

```go
package main
 
import (
    "fmt"
    "time"
)
 
func main() {
    ch := make(chan int)
    go func(c chan int) {
        // 修改时间后,再查看执行结果
        time.Sleep(time.Second * 1)
        ch <- 1
    }(ch)
 
    select {
    case v := <-ch:
        fmt.Print(v)
    case <-time.After(2 * time.Second): // 等待 2s
        fmt.Println("no case ok")
    }
 
    time.Sleep(time.Second * 10)
}
 
我们通过修改上面的时等待时间可以看到，如果等待时间超出<2秒，则输出1，否则打印“no case ok”
```

## **5. 空select{}**

```go
package main
 
func main() {
    select {}
}
goroutine 1 [select (no cases)]:
main.main()
/root/project/practice/mytest/main.go:10 +0x20
exit status 2
直接死锁
```

## **6. for中的select 引起的CPU过高的问题**

```go
package main
 
import (
    "runtime"
    "time"
)
 
func main() {
    quit := make(chan bool)
    for i := 0; i != runtime.NumCPU(); i++ {
        go func() {
            for {
                select {
                case <-quit:
                    break
                default:
                }
            }
        }()
    }
 
    time.Sleep(time.Second * 15)
    for i := 0; i != runtime.NumCPU(); i++ {
        quit <- true
    }
}
```

上面这段代码会把所有CPU都跑满，原因就就在select的用法上。

一般来说，我们用select监听各个case的IO事件，每个case都是阻塞的。上面的例子中，我们希望select在获取到quit通道里面的数据时立即退出循环，但由于他在for{}里面，在第一次读取quit后，仅仅退出了select{}，并未退出for，所以下次还会继续执行select{}逻辑，此时永远是执行default，直到quit通道里读到数据，否则会一直在一个死循环中运行，即使放到一个goroutine里运行，也是会占满所有的CPU。

解决方法就是把default去掉即可，这样select就会一直阻塞在quit通道的IO上， 当quit有数据时，就能够随时响应通道中的信息。