---
title: "golang unsafe.Pointer用法"
date: 2020-06-15T11:32:27+08:00
lastmod: 2020-06-15T11:32:27+08:00
keywords: ["golang","golang基础"]
description: "golang 中的init函数"
tags: ["golang"]
categories: ["golang"]
author: "梁天"
---
unsafe 是关注 Go 程序操作类型安全的包。，使用它要格外小心； unsafe 可以特别危险，但它也可以特别有效。例如，当处理系统调用时，Go 的结构体必须和 C 的结构体拥有相同的内存结构，这时你可能除了使用 unsafe 以外，别无选择。
<!--more-->

## Golang指针与C/C++指针的差别
在Golang支持的数据类型中，是包含指针的，但是Golang中的指针，与C/C++的指针却又不同，笔者觉得主要表现在下面的两个方面：

+ 弱化了指针的操作，在Golang中，指针的作用仅是操作其指向的对象，不能进行类似于C/C++的指针运算，例如指针相减、指针移动等。从这一点来看，Golang的指针更类似于C++的引用
指针类型不能进行转换，如int不能转换为int32
+ 上述的两个限定主

要是为了简化指针的使用，减少指针使用过程中出错的机率，提高代码的鲁棒性。但是在开发过程中，有时需要打破这些限制，对内存进行任意的读写，这里就需要unsafe.Pointer了。

## unsafe.Pointer
### unsafe.Pointer的定义

从unsate.Pointer的定义如下，从定义中我们可以看出，Pointer的本质是一个int的指针：

```go
type ArbitraryType int
type Pointer *ArbitraryType
```
### unsafe.Pointer的功能介绍

下面再来看一下Golang官网对于unsafe.Pointer的介绍：

+ 任意类型的指针值都可以转换为unsafe.Pointer（A pointer value of any type can be converted to a Pointer.）
+ unsafe.Pointer可以转换为任意类型的指针值（A Pointer can be converted to a pointer value of any type.）
+ uintptr可以转换为unsafe.Pointer（A uintptr can be converted to a Pointer.）
+ unsafe.Pointer可以转换为uintptr（A Pointer can be converted to a uintptr.）

从上面的功能介绍可以看到，Pointer允许程序突破Golang的类型系统的限制，任意读写内存，使用时需要额外小心，正如它的包名unsafe所提示的一样。

PS:uintptr本质上是一个用于表示地址值的无符号整数，而不是一个引用，它表示程序中使用的某个对象的地址值。

### 指针类型转换

下面以int64转换为int为例子，说明unsafe.Pointer在指针类型转换时的使用，如下：

```go
func main() {
    i := int64(1)
    var iPtr *int
    // iPtr = &i // 错误
    iPtr = (*int)(unsafe.Pointer(&i))
    fmt.Printf("%d\n", *iPtr)
}
```
注意，这种类型转换，需要保证转换后的类型的大小不大于转换前的类型，且具有相同的内存布局，则可将数据解释为另一个类型。反之，如将int32的指针，转换为int64的指针，在后续的读写中，可能会发生错误。

### 读写结构内部成员

上面的类型转换只是一个简单的例子，在实际开发中，使用unsafe.Pointer进行类型转换一般用于读取结构的私有成员变量或者修改结构的变量，下面以修改一个string变量的值为例子，说明类型转换对于任意内存读写。

我们先来看看在Golang中string是如何定义的：

```go
type stringStruct struct {
    str unsafe.Pointer
    len int
}
```

string的结构由是由一个指向字节数组的unsafe.Pointer和int类型的长度字段组成，我们可以定义一下与其结构相同的类型，并通过unsafe.Pointer把string的指针转换并赋值到新类型的变量中，通过操作该变量来读写string内部的成员。

在Golang中已经存在这样的结构体了，它就是reflect.StringHeader，它的定义如下：

```go
// StringHeader is the runtime representation of a string.
// It cannot be used safely or portably and its representation may
// change in a later release.
// Moreover, the Data field is not sufficient to guarantee the data
// it references will not be garbage collected, so programs must keep
// a separate, correctly typed pointer to the underlying data.
type StringHeader struct {
    Data uintptr
    Len  int
}
```

unsafe.Pointer与uintptr在内存结构上是相同的，下面通过一个原地修改字符串的值来演示相关的操作：


```go
func main() {
    str1 := "hello world"
    hdr1 := (*reflect.StringHeader)(unsafe.Pointer(&str1)) // 注1
    fmt.Printf("str:%s, data addr:%d, len:%d\n", str1, hdr1.Data, hdr1.Len)

    str2 := "abc"
    hdr2 := (*reflect.StringHeader)(unsafe.Pointer(&str2))

    hdr1.Data = hdr2.Data // 注2
    hdr1.Len = hdr2.Len   // 注3
    fmt.Printf("str:%s, data addr:%d, len:%d\n", str1, hdr1.Data, hdr1.Len)
}
```

其运行结果如下：

```go
str:hello world, data addr:4996513, len:11
str:abc, data addr:4992867, len:3
```

代码解释：

+ 注1：该行代码是把str1转化为unsafe.Pointer后，再把unsafe.Pointer转换来StringHeader的指针，然后通过读写hdr1的成员即可读写str1成员的值
+ 注2：通过修改hdr1的Data的值，修改str1的字节数组的指向
+ 注3：为了保证字符串的结果是完整的，通过修改hdr1的Len的值，修改str1的长度字段

最后，str1的值，已经被修改成了str2的值，即"abc"。

### 指针运算

下面的代码，模拟了通过指针移动，遍历slice的功能，其本质思想是，找到slice的第一个元素的地址，然后通过加上slice每个元素所占的大小作为偏移量，实现指针的移动和运算。

```go
func main() {
    data := []byte("abcd")
    for i := 0; i < len(data); i++ {
        ptr := unsafe.Pointer(uintptr(unsafe.Pointer(&data[0])) + uintptr(i)*unsafe.Sizeof(data[0])) 
        fmt.Printf("%c,", *(*byte)(unsafe.Pointer(ptr)))
    }
    fmt.Printf("\n")
}
```
其运行结果如下：

```go
a,b,c,d,
```

代码解释：

要理解上述代码，首选需要了解两个原则，分别是：

+ 其他类型的指针只能转化为unsafe.Pointer，也只有unsafe.Pointer才能转化成任意类型的指针
+ 只有uintptr才支持加减操作，而uintptr是一个非负整数，表示地址值，没有类型信息，以字节为单位

for循环的ptr赋值是该例子中的重点代码，它表示：

1. 把data的第0个元素的地址，转化为unsafe.Pointer，再把它转换成uintptr，用于加减运算，即（uintptr(unsafe.Pointer(&data[0])) ）
2. 加上第i个元素的偏移量，得到一个新的uintptr值，计算方法为i每个元素所占的字节数，即（+ uintptr(i)unsafe.Sizeof(data[0])）
3. 把新的uintptr再转化为unsafe.Pointer，用于在后续的打印操作中，转化为实际类型的指针

## 总结

阅读本文后，希望能让你对unsafe.Pointer有一定的了解，总的来说，它的作用是用于打破类型系统实现更灵活的内存读写。但同时也是不安全的，使用时需要额外小心。

总结一下unsafe.Pointer的使用法则就是：

+ 任意类型的指针值都可以转换为unsafe.Pointer，unsafe.Pointer也可以转换为任意类型的指针值
+ unsafe.Pointer与uintptr可以实现相互转换
+ 可以通过uintptr可以进行加减操作，从而实现指针的运算

## 额外拓展：

uintptr和unsafe.Pointer的区别在哪里？

+ unsafe.Pointer只是单纯的通用指针类型，用于转换不同类型指针，它不可以参与指针运算；
+ 而uintptr是用于指针运算的，GC 不把 uintptr 当指针，也就是说 uintptr 无法持有对象， uintptr 类型的目标会被回收；
+ unsafe.Pointer 可以和 普通指针 进行相互转换；
+ unsafe.Pointer 可以和 uintptr 进行相互转换。

**举例**

通过一个例子加深理解，接下来尝试用指针的方式给结构体赋值。
```go
package main

import (
 "fmt"
 "unsafe"
)

type W struct {
 b int32
 c int64
}

func main() {
 var w *W = new(W)
 //这时w的变量打印出来都是默认值0，0
 fmt.Println(w.b,w.c)

 //现在我们通过指针运算给b变量赋值为10
 b := unsafe.Pointer(uintptr(unsafe.Pointer(w)) + unsafe.Offsetof(w.b))
 *((*int)(b)) = 10
 //此时结果就变成了10，0
 fmt.Println(w.b,w.c)
}
```
uintptr(unsafe.Pointer(w)) 获取了 w 的指针起始值

unsafe.Offsetof(w.b) 获取 b 变量的偏移量

两个相加就得到了 b 的地址值，将通用指针 Pointer 转换成具体指针 ((*int)(b))，通过 * 符号取值，然后赋值。*((*int)(b)) 相当于把 (*int)(b) 转换成 int 了，最后对变量重新赋值成 10，这样指针运算就完成了。