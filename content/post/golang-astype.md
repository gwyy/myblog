---
title: "golang基础 - 自定义类型和类型别名(type)"
date: 2021-11-09T10:49:52+08:00
lastmod: 2021-11-09T10:49:52+08:00
keywords: ["golang""]
description: "Go语言通过type关键字定义自定义类型。自定义类型是全新的类型。
"
tags: ["golang"]
categories: ["golang"]
author: "梁天"
---
区分开自定义类型和类型别名之间的不同，在什么场景下用自定义类型，什么场景下用类型别名。
<!--more-->
## 自定义类型
Go语言通过type关键字定义自定义类型。自定义类型是全新的类型。

```go
// 将newInt定义为int类型
type newInt int

func main() {
	var a newInt
	a = 100
	fmt.Println(a)        // 100
	fmt.Printf("%T\n", a) // main.newInt
}
```
上例中的`newInt`是具有`int`特性的新类型。可以看到变量a的类型是`main.newInt`，这表示`main`包下定义的`newInt`类型。

## 类型别名
语法格式：`type 别名 = Type`
示例：
```go
type tempString = string

func main() {
	var s tempString
	s = "我是s"
	fmt.Println(s)        // 我是s
	fmt.Printf("%T\n", s) // string
}
```
例中，`tempString`是`string`的别名，其本质上与`string`是同一个类型。类型别名只会在代码中存在，编译完成后不会有如`tempString`一样的类型别名。所以变量s的类型是`string`。
字符类型中的`byte`和`rune`就是类型别名：
```go
type byte = uint8
type rune = int32
```
类型别名这个功能非常有用，鉴于go中有些类型写起来非常繁琐，比如json相关的操作中，经常用到map[string]interface {}这种类型，写起来是不是很繁琐，没关系，给它起个简单的别名!这样用起来爽多了。
```go
type strMap2Any = map[string]interface {}
```
