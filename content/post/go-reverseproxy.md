---
title: "golang ReverseProxy源码分析"
date: 2022-03-20T13:15:02+08:00
lastmod: 2022-03-20T13:15:02+08:00
keywords: ["golang","reverse-proxy","源码分析"]
description: "ReverseProxy是golang自带的简单网络Daili工具，仅适合自己测试用，不过麻雀虽小五脏俱全，功能还是挺多的。今天我们一起分析下这个工具的源码。
"
tags: ["golang基础","源码分析"]
categories: ["golang","源码分析"]
author: "梁天"
---
ReverseProxy是golang自带的简单网络Daili工具，仅适合自己测试用，不过麻雀虽小五脏俱全，功能还是挺多的。今天我们一起分析下这个工具的源码。

<!--more-->

### 功能支持

- 支持自定义修改响应内容
- 支持连接池
- 支持错误信息自定义处理
- 支持 websocket 服务
- 支持自定义负载均衡
- 支持 https Daili
- 支持 url 重写



### 简单使用

**最简单使用：**

```go
    //Daili服务器ip
	addr := "127.0.0.1:4001"
	//后端真实服务器ip
	rs1 := "http://127.0.0.1:2000"
	url1, err1 := url.Parse(rs1)
	if err1 != nil {
		log.Println(er
    r1)
	}
    //简单实例化
	proxy := httputil.NewSingleHostReverseProxy(url1)
	log.Println("Starting httpserver at " + addr)
	log.Fatal(http.ListenAndServe(addr, proxy))
```

这样就开启了一个Daili服务器，通过房屋4001端口，就能无缝转发到真实的2000端口上的服务器了。

**url重写**

reverseproxy默认为我们提供了个简单的包装函数 `NewSingleHostReverseProxy` 它在该函数里实现了director逻辑，director逻辑是实现请求转发的核心逻辑。我们可以看下它实现的源码

```go
//url重写
	director := func(req *http.Request) {
		//url_rewrite
		//127.0.0.1:2002/dir/abc ==> 127.0.0.1:2003/base/abc ??
		//127.0.0.1:2002/dir/abc ==> 127.0.0.1:2002/abc
		//127.0.0.1:2002/abc ==> 127.0.0.1:2003/base/abc
		re, _ := regexp.Compile("^/dir(.*)")
		req.URL.Path = re.ReplaceAllString(req.URL.Path, "$1")
		//协议重写 主机赋值
		req.URL.Scheme = url1.Scheme
		req.URL.Host = url1.Host

		//target.Path : /base
		//req.URL.Path : /dir
		req.URL.Path = singleJoiningSlash(url1.Path, req.URL.Path)
		if targetQuery == "" || req.URL.RawQuery == "" {
			req.URL.RawQuery = targetQuery + req.URL.RawQuery
		} else {
			req.URL.RawQuery = targetQuery + "&" + req.URL.RawQuery
		}
		if _, ok := req.Header["User-Agent"]; !ok {
			req.Header.Set("User-Agent", "")
		}
	}
```



**更改返回内容**

ReverseProxy还支持我们修改返回内容，我们可以通过ModfyResponse 属性传递一个匿名方法，该方法里可以编写我们需要修改返回内容的逻辑。

```go
	//更改内容 需要传递一个匿名函数
	modifyFunc := func(resp *http.Response) error {
		if resp.StatusCode != 200 {
			oldPayload, err := ioutil.ReadAll(resp.Body)
			if err != nil {
				return err
			}
			newPayload := []byte("ProxyStatusCode error:" + string(oldPayload))
			resp.Body = ioutil.NopCloser(bytes.NewBuffer(newPayload))
			resp.ContentLength = int64(len(newPayload))
			resp.Header.Set("Content-Length", strconv.FormatInt(int64(len(newPayload)), 10))
		}
		return nil
	}
	proxy.ModifyResponse = modifyFunc
```

我们也可以不使用它提供的`NewSingleHostReverseProxy` 方法，而是自己实现相应的逻辑，最后我们通过实例化一个`ReverseProxy` 对象并注入到http服务器内。

```go
proxy := &httputil.ReverseProxy{Director: director, ModifyResponse: modifyFunc}
log.Println("Starting httpserver at " + addr)
log.Fatal(http.ListenAndServe(addr, proxy))
```

### 请求转发核心逻辑

大家看过golang http包源码的都知道，传入http包的handler主要是实现了 `ServeHTTP` 这个方法。那么我们一起看下ReverseProxy 是怎么实现`ServeHTTP` 的。

#### 拿到连接池

第一步先验证结构体内是否有传入连接池，如果没有就用自己默认的连接池

```go
transport := p.Transport
if transport == nil {
	transport = http.DefaultTransport
}
```

#### 循环判断请求是否终止

接下来就是验证该请求是否终止，我们拿到当前请求的`http.ResponseWriter` 然后向上转型为`http.CloseNotifier`接口。接着我们拿到 `cn.CloseNotify()` 然后就一直开一个协程，判断notifyChan 是否有消息，如果有消息就直接出发cancel() 方法。

```go
ctx := req.Context()
	if cn, ok := rw.(http.CloseNotifier); ok {
		var cancel context.CancelFunc
		ctx, cancel = context.WithCancel(ctx)
		defer cancel()
		notifyChan := cn.CloseNotify()
		go func() {
			select {
			case <-notifyChan:
				cancel()
			case <-ctx.Done():
			}
		}()
	}
```

#### 深度拷贝ctx信息

接下来会用上游的ctx做个深度拷贝，然后对`ContentLength` 、`Body` 、 `Header` 做一些校验

```go
outreq := req.Clone(ctx)
	if req.ContentLength == 0 {
		outreq.Body = nil // Issue 16036: nil Body for http.Transport retries
	}
	if outreq.Body != nil {
		defer outreq.Body.Close()
	}
	if outreq.Header == nil {
		outreq.Header = make(http.Header) // Issue 33142: historical behavior was to always allocate
	}
```

#### 修改request

调用我们设置的Director方法修改最终request， 同时把请求头的Close置为false。也就是说这个连接是可以被复用的。

```go
p.Director(outreq)
outreq.Close = false
```

#### Upgrade头特殊处理

从header里面判断是否有Upgrade 如果有的话就返回Upgrade,否则返回空,接着把header头内的Connection信息清除掉

```go
reqUpType := upgradeType(outreq.Header)
removeConnectionHeaders(outreq.Header)
```

#### 删除请求里面的逐跳标题

因为我们需要一个持久的连接，而不管客户端发送给我们什么，但是针对Te,和trailers仍然做保留

```go
for _, h := range hopHeaders {
	outreq.Header.Del(h)
}
if httpguts.HeaderValuesContainsToken(req.Header["Te"], "trailers") {
	outreq.Header.Set("Te", "trailers")
}
```

#### 判断请求升级

如果upgrade不为空，那么就设置进去

```go
if reqUpType != "" {
	outreq.Header.Set("Connection", "Upgrade")
	outreq.Header.Set("Upgrade", reqUpType)
}
```

#### 追加clientIP信息

通过req请求头里面的RemoteAddr信息，追加到请求头的X-Forwarded-For信息中。

```go
if clientIP, _, err := net.SplitHostPort(req.RemoteAddr); err == nil {
		prior, ok := outreq.Header["X-Forwarded-For"]
		omit := ok && prior == nil // Issue 38079: nil now means don't populate the header
		if len(prior) > 0 {
			clientIP = strings.Join(prior, ", ") + ", " + clientIP
		}
		if !omit {
			outreq.Header.Set("X-Forwarded-For", clientIP)
		}
	}
```

### 下游请求数据

通过连接池，直接请求下游数据。如果请求失败，抛出一个`ErrorHandler`方法并执行。

```go
res, err := transport.RoundTrip(outreq)
	if err != nil {
		p.getErrorHandler()(rw, outreq, err)
		return
	}
```

#### 处理请求升级

如果状态码是101，那么表示要进行请求升级（websocket,h2c,etc）接着执行`modifyResponse` 这时候使用者可以针对101情况做一些特殊的处理。（有兴趣可以看下`handleUpgradeResponse` 方法里的代码，再函数体内部劫持到原始的tcp连接，并且开2个协程持续交换数据直到一方关闭）。最后执行特殊的请求升级的返回。

```go
if res.StatusCode == http.StatusSwitchingProtocols {
	if !p.modifyResponse(rw, res, outreq) {
		return
	}
    p.handleUpgradeResponse(rw, outreq, res)
	return
}
```

#### 移除下游无用header头

移除一些无用的header头

```go
removeConnectionHeaders(res.Header)
for _, h := range hopHeaders {
	res.Header.Del(h)
}
```

#### 修改返回内容

这一步就是调用我们之前定义的modifyResponse 函数了。并且拷贝下游返回的header头信息。另外也会处理一些Trailer头部信息。

```go
if !p.modifyResponse(rw, res, outreq) {
	return
}
copyHeader(rw.Header(), res.Header)	}
```

#### 写入状态码和刷新response

接下来就写入返回的状态码，和周期性刷新内容daoresponse中。

```go
rw.WriteHeader(res.StatusCode)
err = p.copyResponse(rw, res.Body, p.flushInterval(res))
```

#### 关闭body，处理Trailer信息

等数据全部拷贝完成后会关闭body,最后处理下trailer信息。

```go
res.Body.Close()
...
for k, vv := range res.Trailer {
	k = http.TrailerPrefix + k
	for _, v := range vv {
		rw.Header().Add(k, v)
	}
}
```
