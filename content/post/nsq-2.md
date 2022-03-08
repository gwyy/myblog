---
title: "nsq 启动流程讲解"
date: 2022-03-01T20:15:02+08:00
lastmod: 2022-03-01T20:15:02+08:00
keywords: ["golang","nsq","源码分析"]
description: "这篇文章我们就正式的开始分析nsq的代码了，上一篇给大家介绍了下nsq的特性和功能。再分析代码的同时，大家可以比对着我写的nsq精注版代码一遍看一遍调试。这样的效果更佳。"
tags: ["golang","nsq","源码分析"]
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











