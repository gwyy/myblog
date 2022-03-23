---
title: "golang Slice的创建、添加、删除等操作和源码分析"
date: 2022-03-20T13:48:24+08:00
lastmod: 2022-03-20T13:48:24+08:00
keywords: ["golang","golang源码分析","slice","array"]
description: "Go Slice的创建、添加、删除等操作和slice源码分析"
tags: ["golang基础"]
categories: ["golang"]
author: "梁天"
---
本文从源码角度学习 golang slice 的创建、删除、扩容，深拷贝和slice的源码实现。
<!--more-->


golang 中的 *slice* 非常强大，让数组操作非常方便高效。在开发中不定长度表示的数组全部都是 *slice* 。但是很多同学对 *slice* 的模糊认识，造成认为golang中的数组是引用类型，结果就是在实际开发中碰到很多坑，以至于出现一些莫名奇妙的问题，数组中的数据丢失了。

# slice的用法

## 定义slice的几种方式

```go
//声明一个slice,值是nil
var s []int
//静态显式初始化 初始化成一个大小为0的slice.
//此时变量(s == nil)已经不成立了，但是s的大小len(s)还是等于0
//实际上 []string{} == make([]string, 0)。
s := []int{}
//通过make初始化
//第一个是数据类型，第二个是 len ，第三个是 cap 。如果不穿入第三个参数，则 cap=len
s := make([]int,0,3)

//切片生成
var data [10]int
slice := data[2:8]

//append 生成 ，建议append生成的时候预先make指定长度，性能会好上很多
slice := make([]int,0,1000)
slice = append(slice,6)

//第二种append生成方式 性能最优
s := make([]int,1000) //len=1000,cap=1000
for j:=0;j<1000;j++ {
    s[j] = j
}
```



1.当cap < 1024 的时候 slice 每次扩容 * 2

2.当cap >= 1024 的时候， slice每次扩容 * 1.25

3.预先分配内存可以提升性能

4.直接用index赋值而非append可以更进一步提升性能

slice 定义的时候是没有长度的，slice的长度是动态可变的，有点类似java语言中的动态数组。

其他优化：bounds checking elimination

## slice删除

```go
package bechmark
import (
    "testing"
)
var (
    // 原始slice
    origin = []int{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
    // 需要删除的元素
    targetEle = 6
)
// 第一种
func BenchmarkMake(t *testing.B) {
    t.ResetTimer()
    for i := 0; i < t.N; i++ {
        target := make([]int, 0, len(origin))
        for _, item := range origin {
            if item != targetEle {
                target = append(target, item)
            }
        }
    }
}

// 第二种
func BenchmarkReuse(t *testing.B) {
    t.ResetTimer()
    for i := 0; i < t.N; i++ {
        target := origin[:0]
        for _, item := range origin {
            if item != targetEle {
                target = append(target, item)
            }
        }
    }
}

// 第三种
func BenchmarkEditOne(t *testing.B) {
    t.ResetTimer()
    for i := 0; i < t.N; i++ {
        for i := 0; i < len(origin); i++ {
            if origin[i] == targetEle {
                origin = append(origin[:i], origin[i+1:]...)
                i-- // maintain the correct index
            }
        }
    }
}
-----------------------
☁  bechmark  go test -v -bench=. -benchtime=3s -benchmem
goos: darwin
goarch: amd64
pkg: test/bechmark
BenchmarkMake-4         95345845            35.8 ns/op        80 B/op          1 allocs/op
BenchmarkReuse-4        255912920           14.4 ns/op         0 B/op          0 allocs/op
BenchmarkEditOne-4      473434452            7.56 ns/op        0 B/op          0 allocs/op
PASS
ok      test/bechmark   12.915s
```

- 除了第一种方法外，其他方法都对原数据进行了修改；
- 第一种方法适合不污染原slice数据的情况下使用，这种方式也比较简单，大部分学习golang的人也都能想到，不过性能稍差一些，还存在内存分配情况，不过也要看业务需要;
- 第二种方法比较巧妙，创建了一个slice，但是共用原始slice的底层数组；这样就不需要额外分配内存空间，直接在原数据上进行修改。
- 第三种方法也会对底层数组进行修改，思路和前两种正好相反，如果找到需要移除的元素的时候，将其之后的元素前移，覆盖该元素的位置。



## slice翻转

```go
func reverse1(s []int) {
	for i, j := 0, len(s)-1; i < j; i, j = i+1, j-1 {
		s[i], s[j] = s[j], s[i]
	}
}
func reverse2(s []int) {
	for i := 0; i < len(s)/2; i++ {
		s[i], s[len(s)-i-1] = s[len(s)-i-1], s[i]
	}
}

func main() {
	var s []int = []int{1, 2, 3}
	reverse1(s)
	fmt.Printf("s:%v\n", s)
	fmt.Println()
	reverse2(s)
	fmt.Printf("s:%v\n", s)
}

```

## slice传递问题

下面看一段代码：

```go
func TestSlice1(t *testing.T) {
	var s []int
	for i := 0; i < 3; i++ {
		s = append(s, i)
	}
	modifySlice(s)
	fmt.Println(s)
}
func modifySlice(s []int) {
	s = append(s, 2048)
	s[0] = 1024
}
```

聪明的你一眼就能看出来，肯定是打印[1024,1,2,2048]吧，其实不是，运行这段代码后只会打印出 [1024,1,2]。原因就是slice 是按值传递的，这里传递的是s底层的数组的指针。

但是仅仅是共享了slice底层的数组，slice底层的len和cap都是被复制了一份，所以在modifySlice里面的len+1在外层是看不到的。外层的len还是3。

更进一步，如果我们再append一条数据会怎么样呢？

```go
func modifySlice(s []int) {
	s = append(s, 2048)
	s = append(s, 4096)
	s[0] = 1024
}
```

我们可以看到外层打印的slice变成了 **[0,1,2]**。因为modifySlice函数内的slice底层的数组发生了扩容，变成了另一个扩容后的结构体，但是外层的slice还是引用的老的结构体。

<font color="red">由此我们得出： slice 还有array 都按值传递的 (传递的时候会复制内存)，golang里所有数据都是按值传递的，指针也是值的一种</font>

如果没有发生扩容，修改在原来的底层数组内存中

如果发生了扩容，修改会在新的内存中

最后我们如果换成这种方式，外部打印的slice又会成什么样呢？

```go
func modifySlice(s []int) {
	s[0] = 1024
	s = append(s, 2048)
	s = append(s, 4096)
}
```

答案是 [1024,1,2] 我们一行一行分析：

第一行：slice还是老的底层数组，这时候直接修改0下标，外部内部都生效

第二行：slice还是老的底层数组，这时候添加了一位，modfiySlice函数内的s len+1 但是外部的len还是3 所以不会打印出2048

第三部：modifySlice内部的s底层数组扩容，彻底和外部的slice独立成2个slice。



**总结**

1. 不要轻易的对切片append，如果新的切片容量比旧的大的话，需要进行growslice操作，新的地址开辟，数据拷贝
2. 尽量对切片设置初始容量值以避免growslice，类似make([]int,0,100)
3. 切片是一个结构体，保存着切片的容量，实际长度以及数组的地址
4. 切片作为函数参数传入会进行引用拷贝，生成一个新的切片，指向同一个数组

## slice截取

go中的slice是支持截取操作的，虽然使用起来非常的方便，但是有很多坑，稍有不慎就会出现bug且不易排查。

让我们来看一段程序：

```go
package main

import "fmt"

func main() {
  slice := []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}
  s1 := slice[2:5]
  s2 := s1[2:7]
  fmt.Printf("len=%-4d cap=%-4d slice=%-1v n", len(slice), cap(slice), slice)
  fmt.Printf("len=%-4d cap=%-4d s1=%-1v n", len(s1), cap(s1), s1)
  fmt.Printf("len=%-4d cap=%-4d s2=%-1v n", len(s2), cap(s2), s2)
}

```

程序输出：

```go
len=10   cap=10   slice=[0 1 2 3 4 5 6 7 8 9] 
len=3    cap=8    s1=[2 3 4] 
len=5    cap=6    s2=[4 5 6 7 8]
```

s1的长度变成3，cap变为8（默认截取到最大容量）， 但是s2截取s1的第2到第7个元素，左闭右开，很多人想问，s1根本没有那么元素啊，但是实际情况是s2截取到了，并且没有发生数组越界，原因就是s2实际截取的是底层数组，目前slice、s1、s2都是共用的同一个底层数组。

我们继续操作：

```go
fmt.Println("--------append 100----------------")
s2 = append(s2, 100)
```

输出结果是：

```go
--------append 100----------------
len=10   cap=10   slice=[0 1 2 3 4 5 6 7 8 100] 
len=3    cap=8    s1=[2 3 4] 
len=6    cap=6    s2=[4 5 6 7 8 100]
```

我们看到往s2里append数据影响到了slice，正是因为两者底层数组是一样的；但是既然都是共用的同一底层数组，s1为什么没有100，因为s1的len是3所以不会有100。我们继续进行操作：

```go
fmt.Println("--------append 200----------------")
s2 = append(s2, 200)
```

输出结果是：

```go
--------append 200----------------
len=10   cap=10   slice=[0 1 2 3 4 5 6 7 8 100] 
len=3    cap=8    s1=[2 3 4] 
len=7    cap=12   s2=[4 5 6 7 8 100 200]
```

我们看到继续往s2中append一个200，但是只有s2发生了变化，slice并未改变，为什么呢？对，是因为在append完100后，s2的容量已满，再往s2中append，底层数组发生复制，系统分配了一块新的内存地址给s2，s2的容量也翻倍了。

我们继续操作：

```go
fmt.Println("--------modify s1----------------")
s1[2] = 20
```

输出会是什么样呢？

```go
--------modify s1----------------
len=10   cap=10   slice=[0 1 2 3 20 5 6 7 8 100] 
len=3    cap=8    s1=[2 3 20] 
len=7    cap=12   s2=[4 5 6 7 8 100 200]
```

这就很容易理解了，我们对s1进行更新，影响了slice，因为两者共用的还是同一底层数组，s2未发生改变是因为在上一步时底层数组已经发生了变化；

以此来看，slice截取的坑确实很多，极容易出现bug，并且难以排查，大家在使用的时候一定注意。





# slice源码分析

## slice 数据结构

这个是 *slice* 的数据结构，它很简单，一个指向真实 *array* 地址的指针 *ptr* ，*slice* 的长度 *len* 和容量 *cap* 。

```go
type slice struct {
    array unsafe.Pointer  //底层数组
    len   int   //长度
    cap   int   //容量
}
```

Slice 的底层数据结构共分为三部分，如下：

- array：指向所引用的数组指针（ unsafe.Pointer 可以表示任何可寻址的值的指针）
- len：长度，当前引用切片的元素个数,len总是小于等于cap
- cap：容量，当前引用切片的容量（底层数组的元素总数）



其中 *len* 和 *cap* 就是我们在调用 *len(slice)* 和 *cap(slice)* 返回的值。

## slice 创建源码

我们可以看下创建slice的源码：

```go
// maxSliceCap returns the maximum capacity for a slice.
func maxSliceCap(elemsize uintptr) uintptr {
    if elemsize < uintptr(len(maxElems)) {
        return maxElems[elemsize]
    }
    return _MaxMem / elemsize
}

func makeslice(et *_type, len, cap int) slice {
    // NOTE: The len > maxElements check here is not strictly necessary,
    // but it produces a 'len out of range' error instead of a 'cap out of range' error
    // when someone does make([]T, bignumber). 'cap out of range' is true too,
    // but since the cap is only being supplied implicitly, saying len is clearer.
    // See issue 4085.

    // 计算最大可分配长度
    maxElements := maxSliceCap(et.size)
    if len < 0 || uintptr(len) > maxElements {
        panic(errorString("makeslice: len out of range"))
    }

    if cap < len || uintptr(cap) > maxElements {
        panic(errorString("makeslice: cap out of range"))
    }

    // 分配连续区间
    p := mallocgc(et.size*uintptr(cap), et, true)
    return slice{p, len, cap}
}
```

## slice 扩容

```go
// 与append(slice,s)对应的函数growslice
// 通过切片的类型，旧切片的容量和数据得出新切片的容量，新切片跟据容量重新申请一块地址，把旧切片的数据拷贝到新切片中

func growslice(et *_type, old slice, cap int) slice {

// 单纯地扩容，不写数据
 // 如果存储的类型空间为0，  比如说 []struct{}, 数据为空，长度不为空
    if et.size == 0 {
        if cap < old.cap {
            panic(errorString("growslice: cap out of range"))
        }
        // append should not create a slice with nil pointer but non-zero len.
        // We assume that append doesn't need to preserve old.array in this case.
        return slice{unsafe.Pointer(&zerobase), old.len, cap}
    }
// 扩容规则 1.新的容量大于旧的2倍，直接扩容至新的容量
// 2.新的容量不大于旧的2倍，当旧的长度小于1024时，扩容至旧的2倍，否则扩容至旧的5/4倍
    newcap := old.cap
	doublecap := newcap + newcap
	if cap > doublecap {
		newcap = cap
	} else {
		if old.cap < 1024 {
			newcap = doublecap
		} else {
			// Check 0 < newcap to detect overflow
			// and prevent an infinite loop.
			for 0 < newcap && newcap < cap {
				newcap += newcap / 4
			}
			// Set newcap to the requested cap when
			// the newcap calculation overflowed.
			if newcap <= 0 {
				newcap = cap
			}
		}
	}

// 跟据切片类型和容量计算要分配内存的大小
  // 为了加速计算（少用除法，乘法）
    // 对于不同的slice元素大小，选择不同的计算方法
    // 获取需要申请的内存大小	
   var overflow bool
	var lenmem, newlenmem, capmem uintptr))
  switch {
	case et.size == 1:
		lenmem = uintptr(old.len)
		newlenmem = uintptr(cap)
		capmem = roundupsize(uintptr(newcap))
		overflow = uintptr(newcap) > maxAlloc
		newcap = int(capmem)
	case et.size == sys.PtrSize:
		lenmem = uintptr(old.len) * sys.PtrSize
		newlenmem = uintptr(cap) * sys.PtrSize
		capmem = roundupsize(uintptr(newcap) * sys.PtrSize)
		overflow = uintptr(newcap) > maxAlloc/sys.PtrSize
		newcap = int(capmem / sys.PtrSize)
	case isPowerOfTwo(et.size):
		var shift uintptr
		if sys.PtrSize == 8 {
			// Mask shift for better code generation.
			shift = uintptr(sys.Ctz64(uint64(et.size))) & 63
		} else {
			shift = uintptr(sys.Ctz32(uint32(et.size))) & 31
		}
		lenmem = uintptr(old.len) << shift
		newlenmem = uintptr(cap) << shift
		capmem = roundupsize(uintptr(newcap) << shift)
		overflow = uintptr(newcap) > (maxAlloc >> shift)
		newcap = int(capmem >> shift)
	default:
		lenmem = uintptr(old.len) * et.size
		newlenmem = uintptr(cap) * et.size
		capmem, overflow = math.MulUintptr(et.size, uintptr(newcap))
		capmem = roundupsize(capmem)
		newcap = int(capmem / et.size)
	} }

// 异常情况，旧的容量比  
    if overflow || capmem > maxAlloc {
		panic(errorString("growslice: cap out of range"))
    }

    var p unsafe.Pointer
	if et.ptrdata == 0 {
		p = mallocgc(capmem, nil, false)
		// The append() that calls growslice is going to overwrite from old.len to cap (which will be the new length).
		// Only clear the part that will not be overwritten.
 // 清空不需要数据拷贝的部分内存
		memclrNoHeapPointers(add(p, newlenmem), capmem-newlenmem)
	} else {
		// Note: can't use rawmem (which avoids zeroing of memory), because then GC can scan uninitialized memory.
		p = mallocgc(capmem, et, true)
		if lenmem > 0 && writeBarrier.enabled {
			// Only shade the pointers in old.array since we know the destination slice p
			// only contains nil pointers because it has been cleared during alloc.
			bulkBarrierPreWriteSrcOnly(uintptr(p), uintptr(old.array), lenmem-et.size+et.ptrdata)
		}
	}
   // 数据拷贝
	memmove(p, old.array, lenmem)

	return slice{p, old.len, newcap 
}
```



### slice的拷贝

slice的拷贝也是针对切片提供的接口，是深拷贝，可以通过调用copy()函数将src切片中的值拷贝到dst切片中，通过该函数进行的切片拷贝后，针对dst切片进行的操作不会对src产生任何的影响，其拷贝长度是按照src与dst切片中最小的len长度去计算的，runtime.slicecopy源代码如下：

```go
func slicecopy(toPtr unsafe.Pointer, toLen int, fmPtr unsafe.Pointer, fmLen int, width uintptr) int {
	if fmLen == 0 || toLen == 0 {
		return 0
	}

	n := fmLen
	if toLen < n {
		n = toLen
	}

	if width == 0 {
		return n
	}
	
	size := uintptr(n) * width
	if size == 1 {  
    // 如果就1个元素 直接赋值过去就好了
		*(*byte)(toPtr) = *(*byte)(fmPtr)
	} else {
    // 直接进行内存的拷贝，如果slice数据量过大将会影响性能
		memmove(toPtr, fmPtr, size)
	}
	return n
}

```


