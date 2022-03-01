---
title: "Golang Http server包分析 二 源码解析"
date: 2022-02-27T10:49:52+08:00
lastmod: 2022-02-27T10:49:52+08:00
draft: false
keywords: ['golang','http','源码解读']
description: "Golang http 包分析"
tags: ['golang','源码解读']
categories: ['golang']
author: "梁天"
---

该文章是分析golang http-server包的系列文章，本篇是第二篇，核心帮助大家深入http-server包的逻辑。明白http包是如何运转的，如何解析http协议。
<!--more-->
我们继续看，直接进入ListenAndServe函数:
```go
func ListenAndServe(addr string, handler Handler) error {
    server := &Server{Addr: addr, Handler: handler}
    return server.ListenAndServe()
}
```
可以看到，把addr放到一个Server结构中，并且调用ListenAndServer()。这里面向对象的方法，相当于Java中new一个对象的实例，并且调用该实例的方法。
继续进函数：
```go
func (srv *Server) ListenAndServe() error {
    addr := srv.Addr
    if addr == "" {
        addr = ":http"
    }
    ln, err := net.Listen("tcp", addr)
    if err != nil {
        return err
    }
    return srv.Serve(tcpKeepAliveListener{ln.(*net.TCPListener)})
}
```
开了tcp 端口监听，并且返回了个 Serve 函数，把tcp的对象传递进去了。
```go
//2871
func (srv *Server) Serve(l net.Listener) error {
  ...
    var tempDelay time.Duration // how long to sleep on accept failure
    ctx := context.WithValue(baseCtx, ServerContextKey, srv)
    for {
    // Accept()返回底层TCP的连接
        rw, err := l.Accept()
        if err != nil {
            select {
            case <-srv.getDoneChan():
                return ErrServerClosed
            default:
            }
            if ne, ok := err.(net.Error); ok && ne.Temporary() {
           // 处理accept因为网络失败之后的等待时间
                if tempDelay == 0 {
                    tempDelay = 5 * time.Millisecond
                } else {
                    tempDelay *= 2
                }
                if max := 1 * time.Second; tempDelay > max {
                    tempDelay = max
                }
                srv.logf("http: Accept error: %v; retrying in %v", err, tempDelay)
                time.Sleep(tempDelay)
                continue
            }
            return err
        }
        connCtx := ctx
        if cc := srv.ConnContext; cc != nil {
            connCtx = cc(connCtx, rw)
            if connCtx == nil {
                panic("ConnContext returned nil")
            }
        }
        tempDelay = 0
        c := srv.newConn(rw)
        c.setState(c.rwc, StateNew) // before Serve can return
    //在另外的goroutine中处理基于该TCP的HTTP请求，本goroutine可以继续accept TCP连接
        go c.serve(connCtx)
    }
}
```
可以重点关注：
```go
for {
        rw, e := l.Accept()
        ...
        c, err := srv.newConn(rw)
        ...
        go c.serve()
}
```
首先，tcp在监听，然后循环接受请求，建立连接，并且用关键字go开启一个服务并发地处理每一个连接。
继续往下，看serve代码，比较长：
```go
// Serve a new connection.
func (c *conn) serve(ctx context.Context) {
    c.remoteAddr = c.rwc.RemoteAddr().String()
    ctx = context.WithValue(ctx, LocalAddrContextKey, c.rwc.LocalAddr())
   
  // 处理ServeTLS accept的连接
    if tlsConn, ok := c.rwc.(*tls.Conn); ok {
        if d := c.server.ReadTimeout; d != 0 {
                  // 设置TCP的读超时时间
            c.rwc.SetReadDeadline(time.Now().Add(d))
        }
        if d := c.server.WriteTimeout; d != 0 {
                  // 设置TCP的写超时时间
            c.rwc.SetWriteDeadline(time.Now().Add(d))
        }
            // tls协商并判断协商结果
        if err := tlsConn.Handshake(); err != nil {
            // If the handshake failed due to the client not speaking
            // TLS, assume they're speaking plaintext HTTP and write a
            // 400 response on the TLS conn's underlying net.Conn.
            if re, ok := err.(tls.RecordHeaderError); ok && re.Conn != nil && tlsRecordHeaderLooksLikeHTTP(re.RecordHeader) {
                io.WriteString(re.Conn, "HTTP/1.0 400 Bad Request\r\n\r\nClient sent an HTTP request to an HTTPS server.\n")
                re.Conn.Close()
                return
            }
            c.server.logf("http: TLS handshake error from %s: %v", c.rwc.RemoteAddr(), err)
            return
        }
        c.tlsState = new(tls.ConnectionState)
        *c.tlsState = tlsConn.ConnectionState()
            // 用于判断是否使用TLS的NPN扩展协商出非http/1.1和http/1.0的上层协议，如果存在则使用server.TLSNextProto处理请求
        if proto := c.tlsState.NegotiatedProtocol; validNextProto(proto) {
            if fn := c.server.TLSNextProto[proto]; fn != nil {
                h := initALPNRequest{ctx, tlsConn, serverHandler{c.server}}
                fn(c.server, tlsConn, h)
            }
            return
        }
    }
   
    // HTTP/1.x from here on.
    // 下面处理HTTP/1.x的请求
    ctx, cancelCtx := context.WithCancel(ctx)
    c.cancelCtx = cancelCtx
    defer cancelCtx()
　 　// 为c.bufr创建read源，使用sync.pool提高存取效率
    c.r = &connReader{conn: c}
      // read buf长度默认为4096,创建ioReader为c.r的bufio.Reader。用于读取HTTP的request
    c.bufr = newBufioReader(c.r)
  　　 // c.bufw默认长度为4096，4<<10=4096，用于发送response
    c.bufw = newBufioWriterSize(checkConnErrorWriter{c}, 4<<10)
    // 循环处理HTTP请求
 
    for {
    　　　　 // 处理请求并返回封装好的响应
        w, err := c.readRequest(ctx)
            // 判断是否有读取过数据,如果读取过数据则设置TCP状态为active
        if c.r.remain != c.server.initialReadLimitSize() {
            // If we read any bytes off the wire, we're active.
            c.setState(c.rwc, StateActive)
        }
            // 处理http请求错误
        if err != nil {
            const errorHeaders = "\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\n"
 
            switch {
            case err == errTooLarge:
                const publicErr = "431 Request Header Fields Too Large"
                fmt.Fprintf(c.rwc, "HTTP/1.1 "+publicErr+errorHeaders+publicErr)
                c.closeWriteAndWait()
                return
 
            case isUnsupportedTEError(err):
                code := StatusNotImplemented
                fmt.Fprintf(c.rwc, "HTTP/1.1 %d %s%sUnsupported transfer encoding", code, StatusText(code), errorHeaders)
                return
 
            case isCommonNetReadError(err):
                return // don't reply
 
            default:
                publicErr := "400 Bad Request"
                if v, ok := err.(badRequestError); ok {
                    publicErr = publicErr + ": " + string(v)
                }
 
                fmt.Fprintf(c.rwc, "HTTP/1.1 "+publicErr+errorHeaders+publicErr)
                return
            }
        }
 
        // Expect 100 Continue support
            // 如果http首部包含"100-continue"请求
        req := w.req
        if req.expectsContinue() {
                  // "100-continue"的首部要求http1.1版本以上，且http.body长度不为0
            if req.ProtoAtLeast(1, 1) && req.ContentLength != 0 {
                // Wrap the Body reader with one that replies on the connection
                req.Body = &expectContinueReader{readCloser: req.Body, resp: w}
            }
              // 非"100-continue"但首部包含"Expect"字段的请求为非法请求
        } else if req.Header.get("Expect") != "" {
            w.sendExpectationFailed()
            return
        }
        // curReq保存了当前的response，当前代码中主要用于在读失败后调用response中的closeNotifyCh传递信号，此时连接断开
 
        c.curReq.Store(w)
 // 判断是否有后续的数据，req.Body在http.readTransfer函数中设置为http.body类型，registerOnHitEOF注册的就是
        // 遇到EOF时执行的函数http.body.onHitEOF
        if requestBodyRemains(req.Body) {
            registerOnHitEOF(req.Body, w.conn.r.startBackgroundRead)
        } else {
    // 如果没有后续的数据，调用下面函数在新的goroutine中阻塞等待数据的到来，通知finishRequest
            w.conn.r.startBackgroundRead()
        }
     
    // 通过请求找到匹配的handler，然后处理请求并发送响应
        serverHandler{c.server}.ServeHTTP(w, w.req)
        w.cancelCtx()
        if c.hijacked() {
            return
        }
    // 该函数中会结束HTTP请求，发送response
        w.finishRequest()
     // 判断是否需要重用底层TCP连接，即是否退出本函数的for循环，推出for循环将断开连接
        if !w.shouldReuseConnection() {
     // 不可重用底层连接时,如果请求数据过大或设置提前取消读取数据，则调用closeWriteAndWait平滑关闭TCP连接
            if w.requestBodyLimitHit || w.closedRequestBodyEarly() {
                c.closeWriteAndWait()
            }
            return
        }
    // 重用连接，设置底层状态为idle
        c.setState(c.rwc, StateIdle)
        c.curReq.Store((*response)(nil))
 
   // 如果没有通过SetKeepAlivesEnabled设置HTTP keepalive或底层连接已经通过如Server.Close关闭，则直接退出
        if !w.conn.server.doKeepAlives() {
            return
        }
        if d := c.server.idleTimeout(); d != 0 {
    // 如果设置了idle状态超时时间，则调用SetReadDeadline设置底层连接deadline，并调用bufr.Peek等待请求
            c.rwc.SetReadDeadline(time.Now().Add(d))
            if _, err := c.bufr.Peek(4); err != nil {
                return
            }
        }
        c.rwc.SetReadDeadline(time.Time{})
    }
}
```
实际上，精简下：
```go
for{
  w, err := c.readRequest()
  ...
  serverHandler{c.server}.ServeHTTP(w, w.req)
  ...
  w.finishRequest()
}
```
newConn生成的HTTP结构体如下，它表示一条基于TCP的HTTP连接，封装了3个重要的数据结构：server表示HTTP server的"server"；rwc表示底层连接结构体rwc net.Conn；r用于读取http数据的connReader（从rwc读取数据）。后续的request和response都基于该结构体。

下面我们看下readRequest函数处理http请求： 
```go
func (c *conn) readRequest(ctx context.Context) (w *response, err error) {
    if c.hijacked() {
        return nil, ErrHijacked
    }
    var (
        wholeReqDeadline time.Time // or zero if none
        hdrDeadline      time.Time // or zero if none
    )
    t0 := time.Now()
    // 设置读取HTTP的超时时间
    if d := c.server.readHeaderTimeout(); d != 0 {
        hdrDeadline = t0.Add(d)
    }
    // 设置读取整个HTTP的超时时间
    if d := c.server.ReadTimeout; d != 0 {
        wholeReqDeadline = t0.Add(d)
    }
    // 通过SetReadDeadline设置TCP读超时时间
    c.rwc.SetReadDeadline(hdrDeadline)
    if d := c.server.WriteTimeout; d != 0 {
        // 通过defer设置TCP写超时时间，本函数主要处理读请求，在本函数处理完request之后再设置写超时时间
        defer func() {
            c.rwc.SetWriteDeadline(time.Now().Add(d))
        }()
    }
    // 设置读取请求的最大字节数，为DefaultMaxHeaderBytes+4096=1052672，用于防止超大报文攻击
    c.r.setReadLimit(c.server.initialReadLimitSize())
    // 处理老设备的client
    if c.lastMethod == "POST" {
        // RFC 7230 section 3.5 Message Parsing Robustness tolerance for old buggy clients.
        peek, _ := c.bufr.Peek(4) // ReadRequest will get err below
        c.bufr.Discard(numLeadingCRorLF(peek))
    }
    // 从bufr读取request，并返回结构体格式的请求
    req, err := readRequest(c.bufr, keepHostHeader)
    if err != nil {
        // 如果读取的报文超过限制，则返回错误
        if c.r.hitReadLimit() {
            return nil, errTooLarge
        }
        return nil, err
    }
    // 判断是否是go服务所支持的HTTP/1.x的请求
    if !http1ServerSupportsRequest(req) {
        return nil, badRequestError("unsupported protocol version")
    }
 
    c.lastMethod = req.Method
    c.r.setInfiniteReadLimit()
 
    hosts, haveHost := req.Header["Host"]
    isH2Upgrade := req.isH2Upgrade()
    // 判断是否需要Host首部字段
    if req.ProtoAtLeast(1, 1) && (!haveHost || len(hosts) == 0) && !isH2Upgrade && req.Method != "CONNECT" {
        return nil, badRequestError("missing required Host header")
    }
    // 多个Host首部字段
    if len(hosts) > 1 {
        return nil, badRequestError("too many Host headers")
    }
    // 非法Host首部字段值
    if len(hosts) == 1 && !httpguts.ValidHostHeader(hosts[0]) {
        return nil, badRequestError("malformed Host header")
    }
    // 判断首部字段值是否有非法字符
    for k, vv := range req.Header {
        if !httpguts.ValidHeaderFieldName(k) {
            return nil, badRequestError("invalid header name")
        }
        for _, v := range vv {
            if !httpguts.ValidHeaderFieldValue(v) {
                return nil, badRequestError("invalid header value")
            }
        }
    }
    // 响应报文中不包含Host字段
    delete(req.Header, "Host")
 
    ctx, cancelCtx := context.WithCancel(ctx)
    req.ctx = ctx
    req.RemoteAddr = c.remoteAddr
    req.TLS = c.tlsState
    if body, ok := req.Body.(*body); ok {
        body.doEarlyClose = true
    }
 
    // 判断是否超过请求的最大值
    if !hdrDeadline.Equal(wholeReqDeadline) {
        c.rwc.SetReadDeadline(wholeReqDeadline)
    }
 
    w = &response{
        conn:          c,
        cancelCtx:     cancelCtx,
        req:           req,
        reqBody:       req.Body,
        handlerHeader: make(Header),
        contentLength: -1,
        closeNotifyCh: make(chan bool, 1),
 
        // We populate these ahead of time so we're not
        // reading from req.Header after their Handler starts
        // and maybe mutates it (Issue 14940)
        wants10KeepAlive: req.wantsHttp10KeepAlive(),
        wantsClose:       req.wantsClose(),
    }
    if isH2Upgrade {
        w.closeAfterReply = true
    }
    // w.cw.res中保存了response的信息，而response中又保存了底层连接conn，后续将通过w.cw.res.conn写数据
    w.cw.res = w
    // 创建2048字节的写bufio，用于发送response
    w.w = newBufioWriterSize(&w.cw, bufferBeforeChunkingSize)
    return w, nil
}
```
读取HTTP请求，并将其结构化为http.Request
```go
func readRequest(b *bufio.Reader, deleteHostHeader bool) (req *Request, err error) {
    // 封装为textproto.Reader，该结构体实现了读取HTTP的相关方法
    tp := newTextprotoReader(b)
    // 初始化一个Request结构体，该函数后续工作就是填充该变量并返回
    req = new(Request)
 
    // First line: GET /index.html HTTP/1.0
    var s string
    // ReadLine会调用<textproto.(*Reader).ReadLine->textproto.(*Reader).readLineSlice->bufio.(*Reader).ReadLine->
    // bufio.(*Reader).ReadSlic->bufio.(*Reader).fill->http.(*connReader).Read>读取HTTP的请求并填充b.buf，并返回以"\n"作为
    // 分隔符的首行字符串  GET / HTTP/1.1
    if s, err = tp.ReadLine(); err != nil {
        return nil, err
    }
    // putTextprotoReader函数使用sync.pool来保存textproto.Reader变量，通过重用内存来提升在大量HTTP请求下执行效率。
    // 对应函数首部的newTextprotoReader
    defer func() {
        putTextprotoReader(tp)
        if err == io.EOF {
            err = io.ErrUnexpectedEOF
        }
    }()
 
    var ok bool
    // 解析请求方法，请求URL，请求协议
    req.Method, req.RequestURI, req.Proto, ok = parseRequestLine(s)
    if !ok {
        return nil, &badStringError{"malformed HTTP request", s}
    }
    // 判断方法是否包含非法字符
    if !validMethod(req.Method) {
        return nil, &badStringError{"invalid method", req.Method}
    }
    // 获取请求路径，如HTTP请求为"http://127.0.0.1:8000/test"时，rawurl为"/test"
    rawurl := req.RequestURI
    // 判断HTTP协议版本有效性，通常为支持HTTP/1.x
    if req.ProtoMajor, req.ProtoMinor, ok = ParseHTTPVersion(req.Proto); !ok {
        return nil, &badStringError{"malformed HTTP version", req.Proto}
    }
 
    // CONNECT requests are used two different ways, and neither uses a full URL:
    // The standard use is to tunnel HTTPS through an HTTP proxy.
    // It looks like "CONNECT www.google.com:443 HTTP/1.1", and the parameter is
    // just the authority section of a URL. This information should go in req.URL.Host.
    //
    // The net/rpc package also uses CONNECT, but there the parameter is a path
    // that starts with a slash. It can be parsed with the regular URL parser,
    // and the path will end up in req.URL.Path, where it needs to be in order for
    // RPC to work.
    // 处理代理场景，使用"CONNECT"与代理建立连接时会使用完整的URL(带host)
    justAuthority := req.Method == "CONNECT" && !strings.HasPrefix(rawurl, "/")
    if justAuthority {
        rawurl = "http://" + rawurl
    }
 
    if req.URL, err = url.ParseRequestURI(rawurl); err != nil {
        return nil, err
    }
 
    if justAuthority {
        // Strip the bogus "http://" back off.
        req.URL.Scheme = ""
    }
 
    // 解析request首部的key：value
    mimeHeader, err := tp.ReadMIMEHeader()
    if err != nil {
        return nil, err
    }
    req.Header = Header(mimeHeader)
 
    // RFC 7230, section 5.3: Must treat
    //    GET /index.html HTTP/1.1
    //    Host: www.google.com
    // and
    //    GET http://www.google.com/index.html HTTP/1.1
    //    Host: doesntmatter
    // the same. In the second case, any Host line is ignored.
    req.Host = req.URL.Host
    // 如果是上面注释中的第一种需要从req.Header中获取"Host"字段
    if req.Host == "" {
        req.Host = req.Header.get("Host")
    }
    // "Host"字段仅存在于request中，在接收到之后需要删除首部的Host字段，更多参见该变量注释
    if deleteHostHeader {
        delete(req.Header, "Host")
    }
    //处理"Cache-Control"首部
    fixPragmaCacheControl(req.Header)
    // 判断是否是长连接，如果是，则保持连接，反之则断开并删除"Connection"首部
    req.Close = shouldClose(req.ProtoMajor, req.ProtoMinor, req.Header, false)
    // 解析首部字段并填充req内容
    err = readTransfer(req, b)
    if err != nil {
        return nil, err
    }
    // 当HTTP1.1服务尝试解析HTTP2的消息时使用"PRI"方法
    if req.isH2Upgrade() {
        // Because it's neither chunked, nor declared:
        req.ContentLength = -1
 
        // We want to give handlers a chance to hijack the
        // connection, but we need to prevent the Server from
        // dealing with the connection further if it's not
        // hijacked. Set Close to ensure that:
        req.Close = true
    }
    return req, nil
}
```
看下 shouldClose 方法：
```go
func shouldClose(major, minor int, header Header, removeCloseHeader bool) bool {
    // HTTP/1.x以下不支持"connection"指定长连接    if major < 1 {
        return true
    }
 
    conv := header["Connection"]    // 如果首部包含"Connection: close"则断开连接
    hasClose := httpguts.HeaderValuesContainsToken(conv, "close")    // 使用HTTP/1.0时，如果包含"Connection: close"或不包含"Connection: keep-alive"，则使用短连接；    // HTTP/1.1中不指定"Connection"，默认使用长连接
    if major == 1 && minor == 0 {
        return hasClose || !httpguts.HeaderValuesContainsToken(conv, "keep-alive")
    }
    // 如果使用非长连接，且需要删除首部中的Connection字段。在经过proxy或gateway时必须移除Connection首部字段
    if hasClose && removeCloseHeader {
        header.Del("Connection")
    }
 
    return hasClose
}
```
看下readTransfer方法：
```go
func readTransfer(msg interface{}, r *bufio.Reader) (err error) {
    t := &transferReader{RequestMethod: "GET"}
 
    // Unify input
    isResponse := false
    switch rr := msg.(type) {    // 消息为响应时的赋值
    case *Response:
        t.Header = rr.Header
        t.StatusCode = rr.StatusCode
        t.ProtoMajor = rr.ProtoMajor
        t.ProtoMinor = rr.ProtoMinor        // 响应中不需要Connection首部字段，下面函数最后一个参数设置为true，删除该首部字段
        t.Close = shouldClose(t.ProtoMajor, t.ProtoMinor, t.Header, true)
        isResponse = true
        if rr.Request != nil {
            t.RequestMethod = rr.Request.Method
        }    // 消息为请求时的赋值
    case *Request:
        t.Header = rr.Header
        t.RequestMethod = rr.Method
        t.ProtoMajor = rr.ProtoMajor
        t.ProtoMinor = rr.ProtoMinor
        // Transfer semantics for Requests are exactly like those for
        // Responses with status code 200, responding to a GET method
        t.StatusCode = 200
        t.Close = rr.Close
    default:
        panic("unexpected type")
    }
 
    // Default to HTTP/1.1
    if t.ProtoMajor == 0 && t.ProtoMinor == 0 {
        t.ProtoMajor, t.ProtoMinor = 1, 1
    }
 
    // 处理"Transfer-Encoding"首部
    err = t.fixTransferEncoding()
    if err != nil {
        return err
    }
    // 处理"Content-Length"首部,注意此处返回的是真实的消息载体长度
    realLength, err := fixLength(isResponse, t.StatusCode, t.RequestMethod, t.Header, t.TransferEncoding)
    if err != nil {
        return err
    }    // 如果该消息为响应且对应的请求方法为HEAD，如果响应首部包含Content-Length字段，则将此作为响应的ContentLength的值，表示server    // 可以接收到的数据的最大长度，由于该响应没有有效载体，此时不能使用fixLength返回的真实长度0
    if isResponse && t.RequestMethod == "HEAD" {
        if n, err := parseContentLength(t.Header.get("Content-Length")); err != nil {
            return err
        } else {
            t.ContentLength = n
        }
    } else {
        t.ContentLength = realLength
    }
 
    // 处理Trailer首部字段，主要进行有消息校验
    t.Trailer, err = fixTrailer(t.Header, t.TransferEncoding)
    if err != nil {
        return err
    }
 
    // If there is no Content-Length or chunked Transfer-Encoding on a *Response
    // and the status is not 1xx, 204 or 304, then the body is unbounded.
    // See RFC 7230, section 3.3.    // 含body但不是chunked且不包含length字段的响应称为unbounded(无法衡量长度的消息)消息，根据RFC 7230会被关闭
    switch msg.(type) {
    case *Response:
        if realLength == -1 &&
            !chunked(t.TransferEncoding) &&
            bodyAllowedForStatus(t.StatusCode) {
            // Unbounded body.
            t.Close = true
        }
    }
 
    // Prepare body reader. ContentLength < 0 means chunked encoding
    // or close connection when finished, since multipart is not supported yet    // 给t.Body赋值
    switch {    // chunked 场景处理
    case chunked(t.TransferEncoding):        // 如果请求为HEAD或响应状态码为1xx, 204 or 304，则消息不包含有效载体
        if noResponseBodyExpected(t.RequestMethod) || !bodyAllowedForStatus(t.StatusCode) {
            t.Body = NoBody
        } else {            // 下面会创建chunkedReader
            t.Body = &body{src: internal.NewChunkedReader(r), hdr: msg, r: r, closing: t.Close}
        }
    case realLength == 0:
        t.Body = NoBody    // 非chunked且包含有效载体(对应Content-Length)，创建limitReader
    case realLength > 0:
        t.Body = &body{src: io.LimitReader(r, realLength), closing: t.Close}
    default:
        // realLength < 0, i.e. "Content-Length" not mentioned in header        // 此处对于消息有效载体unbounded场景，断开底层连接
        if t.Close {
            // Close semantics (i.e. HTTP/1.0)
            t.Body = &body{src: r, closing: t.Close}
        } else {
            // Persistent connection (i.e. HTTP/1.1) 好像走不到该分支。。。
            t.Body = NoBody
        }
    }
 
    // 为请求/响应结构体赋值并通过指针返回
    switch rr := msg.(type) {
    case *Request:
        rr.Body = t.Body
        rr.ContentLength = t.ContentLength
        rr.TransferEncoding = t.TransferEncoding
        rr.Close = t.Close
        rr.Trailer = t.Trailer
    case *Response:
        rr.Body = t.Body
        rr.ContentLength = t.ContentLength
        rr.TransferEncoding = t.TransferEncoding
        rr.Close = t.Close
        rr.Trailer = t.Trailer
    }
 
    return nil
}
 
// 1.13.3版本的本函数描述有误，下面代码来自最新master分支func (t *transferReader) fixTransferEncoding() error {    // 本函数主要处理"Transfer-Encoding"首部，如果不存在，则直接退出
    raw, present := t.Header["Transfer-Encoding"]
    if !present {
        return nil
    }
    delete(t.Header, "Transfer-Encoding")
 
    // Issue 12785; ignore Transfer-Encoding on HTTP/1.0 requests.    // HTTP/1.0不处理此首部
    if !t.protoAtLeast(1, 1) {
        return nil
    }
    // "Transfer-Encoding"首部字段使用逗号分割
    encodings := strings.Split(raw[0], ",")
    te := make([]string, 0, len(encodings))
 
    // When adding new encodings, please maintain the invariant:
    //   if chunked encoding is present, it must always
    //   come last and it must be applied only once.
    // See RFC 7230 Section 3.3.1 Transfer-Encoding.    // 循环处理各个传输编码，目前仅实现了"chunked"
    for i, encoding := range encodings {
        encoding = strings.ToLower(strings.TrimSpace(encoding))
 
        if encoding == "identity" {
            // "identity" should not be mixed with other transfer-encodings/compressions
            // because it means "no compression, no transformation".
            if len(encodings) != 1 {
                return &badStringError{`"identity" when present must be the only transfer encoding`, strings.Join(encodings, ",")}
            }
            // "identity" is not recorded.
            break
        }
 
        switch {
        case encoding == "chunked":
            // "chunked" MUST ALWAYS be the last
            // encoding as per the  loop invariant.
            // That is:
            //     Invalid: [chunked, gzip]
            //     Valid:   [gzip, chunked]
            if i+1 != len(encodings) {
                return &badStringError{"chunked must be applied only once, as the last encoding", strings.Join(encodings, ",")}
            }
            // Supported otherwise.
 
        case isGzipTransferEncoding(encoding):
            // Supported
 
        default:
            return &unsupportedTEError{fmt.Sprintf("unsupported transfer encoding: %q", encoding)}
        }
 
        te = te[0 : len(te)+1]
        te[len(te)-1] = encoding
    }
 
    if len(te) > 0 {
        // RFC 7230 3.3.2 says "A sender MUST NOT send a
        // Content-Length header field in any message that
        // contains a Transfer-Encoding header field."
        //
        // but also:
        // "If a message is received with both a
        // Transfer-Encoding and a Content-Length header
        // field, the Transfer-Encoding overrides the
        // Content-Length. Such a message might indicate an
        // attempt to perform request smuggling (Section 9.5)
        // or response splitting (Section 9.4) and ought to be
        // handled as an error. A sender MUST remove the
        // received Content-Length field prior to forwarding
        // such a message downstream."
        //
        // Reportedly, these appear in the wild.        // "Transfer-Encoding"就是为了解决"Content-Length"不存在才出现了，因此当存在"Transfer-Encoding"时无需处理"Content-Length"，        // 此处删除"Content-Length"首部，不在fixLength函数中处理
        delete(t.Header, "Content-Length")
        t.TransferEncoding = te
        return nil
    }
 
    return nil
}
 
// 本函数处理Content-Length首部，并返回真实的消息载体长度func fixLength(isResponse bool, status int, requestMethod string, header Header, te []string) (int64, error) {
    isRequest := !isResponse
    contentLens := header["Content-Length"]
 
    // Hardening against HTTP request smuggling
    if len(contentLens) > 1 {
        // Per RFC 7230 Section 3.3.2, prevent multiple
        // Content-Length headers if they differ in value.
        // If there are dups of the value, remove the dups.
        // See Issue 16490.        // 下面按照RFC 7230的建议进行处理，如果一个Content-Length包含多个不同的value，则认为该消息无效
        first := strings.TrimSpace(contentLens[0])
        for _, ct := range contentLens[1:] {
            if first != strings.TrimSpace(ct) {
                return 0, fmt.Errorf("http: message cannot contain multiple Content-Length headers; got %q", contentLens)
            }
        }
 
        // 如果一个Content-Length包含多个相同的value，则仅保留一个
        header.Del("Content-Length")
        header.Add("Content-Length", first)
 
        contentLens = header["Content-Length"]
    }
 
    // 处理HEAD请求
    if noResponseBodyExpected(requestMethod) {
        // For HTTP requests, as part of hardening against request
        // smuggling (RFC 7230), don't allow a Content-Length header for
        // methods which don't permit bodies. As an exception, allow
        // exactly one Content-Length header if its value is "0".        // 当HEAD请求中的Content-Length为0时允许存在该字段
        if isRequest && len(contentLens) > 0 && !(len(contentLens) == 1 && contentLens[0] == "0") {
            return 0, fmt.Errorf("http: method cannot contain a Content-Length; got %q", contentLens)
        }
        return 0, nil
    }    // 处理状态码为1xx的响应，不包含消息体
    if status/100 == 1 {
        return 0, nil
    }    // 处理状态码为204和304的响应，不包含消息体
    switch status {
    case 204, 304:
        return 0, nil
    }
 
    // 包含Transfer-Encoding时无法衡量数据长度,以Transfer-Encoding为准，设置返回长度为-1，直接返回
    if chunked(te) {
        return -1, nil
    }
     
    var cl string    // 获取Content-Length字段值
    if len(contentLens) == 1 {
        cl = strings.TrimSpace(contentLens[0])
    }    // 对Content-Length字段的值进行有效性验证,如果有效则返回该值的整型，无效返回错误
    if cl != "" {
        n, err := parseContentLength(cl)
        if err != nil {
            return -1, err
        }
        return n, nil
    }    // 数值为空，删除该首部字段
    header.Del("Content-Length")
    // 请求中没有Content-Length且没有Transfer-Encoding字段的请求被认为没有有效载体
    if isRequest {
        // RFC 7230 neither explicitly permits nor forbids an
        // entity-body on a GET request so we permit one if
        // declared, but we default to 0 here (not -1 below)
        // if there's no mention of a body.
        // Likewise, all other request methods are assumed to have
        // no body if neither Transfer-Encoding chunked nor a
        // Content-Length are set.
        return 0, nil
    }
 
    // Body-EOF logic based on other methods (like closing, or chunked coding)    // 消息为响应，该场景后续会在readTransfer被close处理
    return -1, nil
}
 
func (cr *connReader) startBackgroundRead() {
    cr.lock()
    defer cr.unlock()    // 表示该连接正在被读取
    if cr.inRead {
        panic("invalid concurrent Body.Read call")
    }    // 表示该连接上是否还有数据
    if cr.hasByte {
        return
    }
    cr.inRead = true    // 设置底层连接deadline为1<<64 -1
    cr.conn.rwc.SetReadDeadline(time.Time{})    // 在新的goroutine中等待数据
    go cr.backgroundRead()
}
 
 
func (cr *connReader) backgroundRead() {    // 阻塞等待读取一个字节的数
    n, err := cr.conn.rwc.Read(cr.byteBuf[:])
    cr.lock()    // 如果存在数据则设置cr.hasByte为true,byteBuf容量为1
    if n == 1 {
        cr.hasByte = true
        // We were past the end of the previous request's body already
        // (since we wouldn't be in a background read otherwise), so
        // this is a pipelined HTTP request. Prior to Go 1.11 we used to
        // send on the CloseNotify channel and cancel the context here,
        // but the behavior was documented as only "may", and we only
        // did that because that's how CloseNotify accidentally behaved
        // in very early Go releases prior to context support. Once we
        // added context support, people used a Handler's
        // Request.Context() and passed it along. Having that context
        // cancel on pipelined HTTP requests caused problems.
        // Fortunately, almost nothing uses HTTP/1.x pipelining.
        // Unfortunately, apt-get does, or sometimes does.
        // New Go 1.11 behavior: don't fire CloseNotify or cancel
        // contexts on pipelined requests. Shouldn't affect people, but
        // fixes cases like Issue 23921. This does mean that a client
        // closing their TCP connection after sending a pipelined
        // request won't cancel the context, but we'll catch that on any
        // write failure (in checkConnErrorWriter.Write).
        // If the server never writes, yes, there are still contrived
        // server & client behaviors where this fails to ever cancel the
        // context, but that's kinda why HTTP/1.x pipelining died
        // anyway.
    }
    if ne, ok := err.(net.Error); ok && cr.aborted && ne.Timeout() {
        // Ignore this error. It's the expected error from
        // another goroutine calling abortPendingRead.
    } else if err != nil {
        cr.handleReadError(err)
    }
    cr.aborted = false
    cr.inRead = false
    cr.unlock()    // 当有数据时，通知cr.cond.Wait解锁
    cr.cond.Broadcast()
}
```
```go
func (w *response) finishRequest() {
    w.handlerDone.setTrue()
    // wroteHeader表示是否已经将响应首部写入，没有则写入
    if !w.wroteHeader {
        w.WriteHeader(StatusOK)
    }
    // 此处调用w.cw.write(checkConnErrorWriter) -> c.rwc.write发送数据，即调用底层连接的write将buf中的数据发送出去
    w.w.Flush()    // 将w.w重置并放入sync.pool中，待后续重用
    putBufioWriter(w.w)        // 主要构造chunked的结束符:"0\r\n"，"\r\n"，通过cw.chunking判断是否是chunked编码
    w.cw.close()    // 发送bufw缓存的数据
    w.conn.bufw.Flush()
    // 用于等待处理未读取完的数据，与connReader.backgroundRead中的cr.cond.Broadcast()对应
    w.conn.r.abortPendingRead()
 
    // Close the body (regardless of w.closeAfterReply) so we can
    // re-use its bufio.Reader later safely.
    w.reqBody.Close()
 
    if w.req.MultipartForm != nil {
        w.req.MultipartForm.RemoveAll()
    }
}
```
```go
func (w *response) shouldReuseConnection() bool {    // 表示是否需要在响应之后关闭底层连接。requestTooLarge，isH2Upgrade或包含首部字段"Connection:close"时置位
    if w.closeAfterReply {
        // The request or something set while executing the
        // handler indicated we shouldn't reuse this
        // connection.
        return false
    }
    // 写入数据与"content-length"不匹配,为避免不同步，不重用连接
    if w.req.Method != "HEAD" && w.contentLength != -1 && w.bodyAllowed() && w.contentLength != w.written {
        // Did not write enough. Avoid getting out of sync.
        return false
    }
 
    // There was some error writing to the underlying connection
    // during the request, so don't re-use this conn.    // 底层连接出现错误，不可重用
    if w.conn.werr != nil {
        return false
    }
    // 判断是否在读取完数据前执行关闭
    if w.closedRequestBodyEarly() {
        return false
    }
 
    return true
}
```
```go
// closeWrite flushes any outstanding data and sends a FIN packet (if
// client is connected via TCP), signalling that we're done. We then
// pause for a bit, hoping the client processes it before any
// subsequent RST.
//
// See https://golang.org/issue/3595
func (c *conn) closeWriteAndWait() {
   // 在关闭写之前将缓冲区中的数据发送出去
   c.finalFlush()
   if tcp, ok := c.rwc.(closeWriter); ok {
      // 执行tcpsock.go中的TCPConn.CloseWrite，调用SHUT_WR关闭写
      tcp.CloseWrite()
   }
   time.Sleep(rstAvoidanceDelay)
}
```
```go
func (c *conn) finalFlush() {    // 本函数中如果c.bufr或c.bufw不为空，都会重置并重用这部分内存
    if c.bufr != nil {
        // Steal the bufio.Reader (~4KB worth of memory) and its associated
        // reader for a future connection.
        putBufioReader(c.bufr)
        c.bufr = nil
    }
 
    if c.bufw != nil {        // 将缓存区中的数据全部通过底层发送出去        // respose写数据调用为c.bufw.wr.Write -> checkConnErrorWriter.write -> c.rwc.write，最终通过底层write发送数据
        c.bufw.Flush()
        // Steal the bufio.Writer (~4KB worth of memory) and its associated
        // writer for a future connection.
        putBufioWriter(c.bufw)
        c.bufw = nil
    }
}
```
