---
title: "Golang Http server包分析 一 初识"
date: 2022-02-27T10:49:52+08:00
lastmod: 2022-02-27T10:49:52+08:00
draft: false
keywords: ['golang','http','源码分析']
description: "Golang http 包分析"
tags: ['golang','源码分析']
categories: ['golang']
author: "梁天"
---

  该文章是分析golanghttp包的系列文章，本篇是第一篇，核心帮助大家了解和熟悉golang http包的整体逻辑。希望大家看完后能有所收货，有问题可以在博客留言板和我留言。

<!--more-->

  首先，熟悉http协议的都知道，http协议是基于TCP实现的。

  http服务器的工作方式大概就是监听socket端口，接受连接，获取到请求，处理请求，返回响应。

 所以，对应的会有几个部分

1. Request：用户请求的信息。post、get、url等这些信息

2. Response: 返回给客户端的信息

3. Conn: 用户每次的连接请求

4. Handler：处理请求和返回信息的逻辑处理

### 演示

我们直接调用2个方法就可以开启一个http服务器。

```go
func hello(w http.ResponseWriter,r *http.Request) {
    w.Write([]byte("hello!\r\n"))
}
func main() {
    http.HandleFunc("/",hello)
    err := http.ListenAndServe("0.0.0.0:8889",nil)
    if err != nil {
        fmt.Println(err)
    }
}
```

### 代码分析

先分析一下`http.HandleFunc()`这个函数。直接进入函数`HandleFunc`的声明，源码如下:

```go
//2451行
func HandleFunc(pattern string, handler func(ResponseWriter, *Request)) {
    DefaultServeMux.HandleFunc(pattern, handler)
}
```

对于DefaultServeMux在源代码中的声明如下

```go
type ServeMux struct {
    mu    sync.RWMutex
    m     map[string]muxEntry
    hosts bool // whether any patterns contain hostnames
}

type muxEntry struct {
    explicit bool
    h        Handler
    pattern  string
}

// NewServeMux allocates and returns a new ServeMux.
func NewServeMux() *ServeMux {
    return &ServeMux{m: make(map[string]muxEntry)}
}

// DefaultServeMux is the default ServeMux used by Serve.
var DefaultServeMux = NewServeMux()
```

这里DefaultServeMux调用了HandleFunc()，参数就是传进来的`“/”`和`HandleFunc`（定义一个函数类型，就可以把函数作为参数传入）

```go
//2435行
func (mux *ServeMux) HandleFunc(pattern string, handler func(ResponseWriter, *Request)) {
    if handler == nil {
        panic("http: nil handler")
    }
    mux.Handle(pattern, HandlerFunc(handler))
}
```

HandlerFunc 是ServeMux 结构体的方法，这里先分析`HandlerFunc(handler)`，也就是把`func(ResponseWriter, *Request)`函数类型转换为`HandlerFunc`类型（注意！是HandlerFunc，不是HandleFunc）

HandlerFunc这里定义了一个`func(ResponseWriter, *Request)`的函数类型，`HandlerFunc(handler)`实际上就是handler本身。为什么这么做？

```go
type HandlerFunc func(ResponseWriter, *Request)

// ServeHTTP calls f(w, r).
func (f HandlerFunc) ServeHTTP(w ResponseWriter, r *Request) {
    f(w, r)
}
```

HandlerFunc实现了`ServeHTTP(w ResponseWriter, r *Request)` 这个方法！！！！里面只有一行代码`f(w, r)`,也就是说实际上是调用handler，也就是我们一开始在`http.HandleFunc("/", HandleRequest)`中自己定义的函数HandleRequest。

而 HandlerFunc 实现了 ServeHTTP的方法，其实就是实现了 Handler 接口。

 HandlerFunc实现Handler接口里面的方法。跟Java里面的接口一样，任何实现接口的类型，都可以向上转换为该接口类型。这就意味着HandlerFunc类型的值可以自动转换为Handler类型的值作为参数传进任何函数中。这很重要！回头看看muxEntry结构体里面的两个变量`pattern string`和`h Handler`，不正好对应刚才传入的参数`pattern, HandlerFunc(handler)`吗！！

所以，`HandlerFunc(handler)`就是一个适配器模式！HandlerFunc实现Handler接口，ServeHTTP方法里面调用的实际上是我们一开始定义的函数HandleRequest。

这样的一个好处就是，`func(ResponseWriter,*Request)` -> `HandlerFunc` -> `Handler` ，那定义的函数HandleRequest可以作为Handler类型的一个参数。调用Handler的ServeHTTP方法，也就是调用定义的函数HandleRequest。

理解完`HandlerFunc(handler)`，再来看看整句`mux.Handle(pattern, HandlerFunc(handler))`

```go
//2391
func (mux *ServeMux) Handle(pattern string, handler Handler) {
    mux.mu.Lock()
    defer mux.mu.Unlock()

    if pattern == "" {
        panic("http: invalid pattern")
    }
    if handler == nil {
        panic("http: nil handler")
    }
    if _, exist := mux.m[pattern]; exist {
        panic("http: multiple registrations for " + pattern)
    }
    if mux.m == nil {
        mux.m = make(map[string]muxEntry)
    }
    e := muxEntry{h: handler, pattern: pattern}
    mux.m[pattern] = e
    if pattern[len(pattern)-1] == '/' {
        mux.es = appendSorted(mux.es, e)
    }
    if pattern[0] != '/' {
        mux.hosts = true
    }
}
```

这里的代码直接关注到第17行和37行

由于37行的代码是经过判断后进入if的语句，所以别扣细节，直接关注第17行。

```go
mux.m[pattern] = muxEntry{explicit: true, h: handler, pattern: pattern}
```

都是赋值语句，基本逻辑都是为DefaultServeMux里面的map赋值。

这里就是把传进来的pattern和handler保存在muxEntry结构中，并且pattern作为key，把muxEntry装入到DefaultServeMux的Map里面。

 至此，第一个关键的函数`http.HandleFunc("/", HandleRequest)`就分析完了，就是把当前的参数`"/", HandleRequest`保存在http包里面的默认的一个ServeMux结构中的map中,简单来说就是保存当前路由和自己定义的那个处理函数。虽然理顺思路感觉挺简单，但是不得不赞叹设计得实在太妙了.
