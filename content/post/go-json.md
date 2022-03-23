---
title: "golang Json用法"
date: 2020-07-15T11:32:08+08:00
lastmod: 2020-07-15T11:32:08+08:00
keywords: ["golang","golang基础"]
description: "Golang Json用法"
tags: ["golang基础"]
categories: ["golang"]
author: "梁天"
---
本篇文章我们一起了解下golang里面json的用法。
<!--more-->

## json简介

json格式可以算我们日常最常用的序列化格式之一了，Go语言作为一个由Google开发，号称互联网的C语言的语言，自然也对JSON格式支持很好。但是Go语言是个强类型语言，对格式要求极其严格而JSON格式虽然也有类型，但是并不稳定，Go语言在解析来源为非强类型语言时比如PHP等序列化的JSON时，经常遇到一些问题诸如字段类型变化导致无法正常解析的情况，导致服务不稳定。下面我们就一起来看看。

## Golang解析JSON之Tag篇

下面看看一个正常的结构体转json是什么样子：

```go
package main
import (
    "encoding/json"
    "fmt"
)
  
// Product 商品信息
type Product struct {
    Name      string
    ProductID int64
    Number    int
    Price     float64
    IsOnSale  bool
}
  
func main() {
    p := &Product{}
    p.Name = "Xiao mi 6"
    p.IsOnSale = true
    p.Number = 10000
    p.Price = 2499.00
    p.ProductID = 1
    data, _ := json.Marshal(p)
    fmt.Println(string(data))
}
//结果
{"Name":"Xiao mi 6","ProductID":1,"Number":10000,"Price":2499,"IsOnSale":true}
```
何为Tag，tag就是标签，给结构体的每个字段打上一个标签，标签冒号前是类型，后面是标签名

```go
// Product _
type Product struct {
    Name      string  `json:"name"`
    ProductID int64   `json:"-"` // 表示不进行序列化
    Number    int     `json:"number"`
    Price     float64 `json:"price"`
    IsOnSale  bool    `json:"is_on_sale,string"`
}
  
// 序列化过后，可以看见
   {"name":"Xiao mi 6","number":10000,"price":2499,"is_on_sale":"false"}
```

omitempty，tag里面加上omitempy，可以在序列化的时候忽略0值或者空值

```go
package main
  
import (
    "encoding/json"
    "fmt"
)
  
// Product _
type Product struct {
    Name      string  `json:"name"`
    ProductID int64   `json:"product_id,omitempty"`
    Number    int     `json:"number"`
    Price     float64 `json:"price"`
    IsOnSale  bool    `json:"is_on_sale,omitempty"`
}
  
func main() {
    p := &Product{}
    p.Name = "Xiao mi 6"
    p.IsOnSale = false
    p.Number = 10000
    p.Price = 2499.00
    p.ProductID = 0
  
    data, _ := json.Marshal(p)
    fmt.Println(string(data))
}
// 结果
{"name":"Xiao mi 6","number":10000,"price":2499}
```

type，有些时候，我们在序列化或者反序列化的时候，可能结构体类型和需要的类型不一致，这个时候可以指定,支持string,number和boolean

注意：这个地方有个问题，实测go版本 1.14.2  如果字符串是 "" 那么会报错：json: invalid number literal, trying to unmarshal "\"\"" into Number

<font color=red>注意：这个地方有个问题，实测go版本 1.14.2  如果字符串是 "" 那么会报错：json: invalid number literal, trying to unmarshal "\"\"" into Number </font>

```go
package main
  
import (
    "encoding/json"
    "fmt"
)
  
// Product _
type Product struct {
    Name      string  `json:"name"`
    ProductID int64   `json:"product_id,string"`
    Number    int     `json:"number,string"`
    Price     float64 `json:"price,string"`
    IsOnSale  bool    `json:"is_on_sale,string"`
}
  
func main() {
  
    var data = `{"name":"Xiao mi 6","product_id":"10","number":"10000","price":"2499","is_on_sale":"true"}`
    p := &Product{}
    err := json.Unmarshal([]byte(data), p)
    fmt.Println(err)
    fmt.Println(*p)
}
// 结果
<nil>
{Xiao mi 6 10 10000 2499 true}
```
Json.Number 和type差不多 也是实现 string,int 相互转换的，也是一样有上面的问题，当在字符串 “” 的时候 会json转换失败，但是低版本（1.13.0） go是不会报错的
```go
type Test1 struct {
        Name      json.Number  `json:"name"`
        ProductID int64   `json:"product_id"`
        Number    int     `json:"number"`
        Price     float64 `json:"price"`
    }
     cc := `{
    "name":"",
    "product_id":22,
    "number":333}`
 
    var p1 Test1
    err := json.Unmarshal([]byte(cc),&p1)
    fmt.Println(err)
 
    fmt.Println(p1.Name)
```

## 一个字段多个类型终极解决方案：

在很多业务场景下，比如说php返回的json，可能 id有时候是 1 有时候是 "1",你是无法保证的，通过tag和 json.Number ，我实测在""空字符串下会报错。所以需要你自己实现一个类型，然后实现对应的  MarshalJSON 和UnmarshalJSON 就可以了，下面看看代码：

```go
//转换成int
func (g *Gint) UnmarshalJSON(data []byte) error {
    if (data == nil) {
        *g = 0
        return nil
    }
    data = bytes.Trim(data, "\"")
    if len(data) == 0 {
        *g = 0
        return nil
    }
 
    if bytes.Equal(data, []byte("null")) {
        *g = 0
        return nil
    }
    in,err := strconv.Atoi(string(data))
    if err != nil {
        *g = 0
        return nil;
    }
    *g = Gint(in)
    return nil
}
//转换成json
func (g *Gint) MarshalJSON() (data []byte, err error) {
    return json.Marshal(g)
}
func main() {
    type Test1 struct {
        Name      Gint  `json:"name"`
        ProductID int64   `json:"product_id"`
        Number    int     `json:"number"`
        Price     float64 `json:"price"`
    }
     cc := `{
    "name":"1",
    "product_id":22,
    "number":333}`
 
    var p1 Test1
    err := json.Unmarshal([]byte(cc),&p1)
    fmt.Println(err)
    d := 1
    dd := d+ int(p1.Name)
    fmt.Println(p1.Name)
    fmt.Println(dd)
}
```

上面代码，我为 int 类型定义了一个类型别名 Gint,并且实现了 UnmarshalJSON  和 marshalJSON 方法，支持了 “” “11” “abc” "null" 的字符串和 1，2，3，-4 常规的int。 UnmarshalJSON内部屏蔽了报错，尽量保证json成功转换而不报错。

