---
title: "golang 中的init函数"
date: 2020-08-16T11:32:04+08:00
lastmod: 2020-08-16T11:32:04+08:00
keywords: ["golang","golang基础"]
description: "golang 中的init函数"
tags: ["golang"]
categories: ["golang"]
author: "梁天"
---
go语言中init函数用于包(package)的初始化，该函数是go语言的一个重要特性，

<!--more-->

有下面的特征：

1. init函数是用于程序执行前做包的初始化的函数，比如初始化包里的变量等
2. 每个包可以拥有多个init函数
3. 包的每个源文件也可以拥有多个init函数
4. 同一个包中多个init函数的执行顺序go语言没有明确的定义  （应该是顺序执行）
5. 不同包的init函数按照包导入的依赖关系决定该初始化函数的执行顺序
6. init函数不能被其他函数调用，而是在main函数执行之前，自动被调用

下面演示一个文件中可以有多个init函数，执行顺序是从上往下执行。  
```go
//aaa.go
package core
import "fmt"
func init() {
	fmt.Println("core aaa init")
}
func init() {
	fmt.Println("core aaa init2")
}
func Show() {
	fmt.Println("core show")
}
```
下面是core包中的另一个文件也是有init函数。

```go
//bbb.go
package core
import "fmt"
func init() {
    fmt.Println("core bbb init")
}
```
执行main方法的时候会输出三行：

```go
core aaa init
core aaa init2
core bbb init
```
一般来说，如果只需要一个包的  init函数，不需要这个包另外的方法，可以这么写，这样就表示只执行这个包的 init函数。

```go
_ "github.com/goinaction/code/chapter3/dbdriver/postgres"
```