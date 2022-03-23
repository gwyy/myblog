---
title: "golang switch的用法"
date: 2020-09-14T09:52:55+08:00
lastmod: 2020-09-14T09:52:55+08:00
keywords: ["golang","golang基础"]
description: "Golang switch的用法"
tags: ["golang基础"]
categories: ["golang"]
author: "梁天"
---
最近一直在写go, switch说实话用的不算多。但是今天用了下发现go的switch可真不太一样啊。

<!--more-->

## 无需break
该代码只会匹配到 case 0 ，go会帮你隐式break掉。

```go
func main() {
    i := 0
    switch i {
        case 0:
            fmt.Println("0000000000")
            fmt.Println("0")
        case 1:
            fmt.Println("1111111111")
            fmt.Println("1")
        case 2:
            fmt.Println("2222222222")
            fmt.Println("2")
        default:
            fmt.Println("3333333")
    }
```

## default case
我们每只手只有 5 根手指，但是如果我们输入一个错误的手指序号会发生什么呢？这里就要用到 default 语句了。当没有其他 case 匹配时，将执行 default 语句。
```go
func main() { 
    switch finger := 8; finger {//finger is declared in switch
    case 1:
        fmt.Println("Thumb")
    case 2:
        fmt.Println("Index")
    case 3:
        fmt.Println("Middle")
    case 4:
        fmt.Println("Ring")
    case 5:
        fmt.Println("Pinky")
    default: //default case
        fmt.Println("incorrect finger number")
    }
}
```
在上面的程序中，finger 的值为 8，它不匹配任何 case，因此打印 incorrect finger number。default 语句不必放在 switch 语句的最后，而可以放在 switch 语句的任何位置。

你也许发现了另外一个小的改变，就是将 finger 声明在了 switch 语句中。switch 语句可以包含一个可选的语句，该语句在表达式求值之前执行。在 switch finger := 8; finger 这一行中， finger 首先被声明，然后作为表达式被求值。这种方式声明的 finger 只能在 switch 语句中访问。

## switch语句对case表达式的结果类型有如下要求

要求case表达式的结果能转换为switch表示式结果的类型

并且如果switch或case表达式的是无类型的常量时，会被自动转换为此种常量的默认类型的值。比如整数1的默认类型是int, 浮点数3.14的默认类型是float64

```go
func main() {
    func main() {
    value1 := [...]int8{0, 1, 2, 3, 4, 5, 6}
    switch 1 + 3 {
        case value1[0], value1[1]:
        fmt.Println("0 or 1")
        case value1[2], value1[3]:
        fmt.Println("2 or 3")
        case value1[4], value1[5], value1[6]:
        fmt.Println("4 or 5 or 6")
        }
    }
}
```
switch 表达式的结果是int类型，case表达式的结果是int8类型，而int8不能转换为int类型，所以上述会报错误

```go
./main.go:10:1: invalid case value1[0] in switch on 1 + 3 (mismatched types int8 and int)
```
## 包含多个表达式的 case

```go
func main() { 
    letter := "i"
    switch letter {
    case "a", "e", "i", "o", "u": //multiple expressions in case
        fmt.Println("vowel")
    default:
        fmt.Println("not a vowel")
    }
```
上面的程序检测 letter 是否是元音。case "a", "e", "i", "o", "u": 这一行匹配所有的元音。程序的输出为：vowel。

## 没有表达式的 switch

switch 中的表达式是可选的，可以省略。如果省略表达式，则相当于 switch true，这种情况下会将每一个 case 的表达式的求值结果与 true 做比较，如果相等，则执行相应的代码。 

```go
func main() { 
    num := 75
    switch { // expression is omitted
    case num >= 0 && num <= 50:
        fmt.Println("num is greater than 0 and less than 50")
    case num >= 51 && num <= 100:
        fmt.Println("num is greater than 51 and less than 100")
    case num >= 101:
        fmt.Println("num is greater than 100")
    }
}
```
在上面的程序中，switch 后面没有表达式因此被认为是 switch true 并对每一个 case 表达式的求值结果与 true 做比较。case num >= 51 && num <= 100:的求值结果为 true，因此程序输出：num is greater than 51 and less than 100。这种类型的 switch 语句可以替代多重 if else 子句。

## fallthrough

在 Go 中执行完一个 case 之后会立即退出 switch 语句。fallthrough语句用于标明执行完当前 case 语句之后按顺序执行下一个case 语句。 让我们写一个程序来了解 fallthrough。下面的程序检测 number 是否小于 50，100 或 200。例如，如果我们输入75，程序将打印 75 小于 100 和 200，这是通过 fallthrough 语句实现的。

这里要注意：**fallthrough强制执行后面的case代码，fallthrough不会判断下一条case的expr结果是否为true。**

```go
func number() int { 
        num := 15 * 5
        return num
}
 
func main() {
 
    switch num := number(); { //num is not a constant
    case num < 50:
        fmt.Printf("%d is lesser than 50\n", num)
        fallthrough
    case num < 100:
        fmt.Printf("%d is lesser than 100\n", num)
        fallthrough
    case num < 200:
        fmt.Printf("%d is lesser than 200", num)
    }
 
}
```

switch 与 case 中的表达式不必是常量，他们也可以在运行时被求值。在上面的程序中 num 初始化为函数 number() 的返回值。程序首先对 switch 中的表达式求值，然后依次对每一个case 中的表达式求值并与 true 做匹配。匹配到 case num < 100: 时结果是 true，因此程序打印：75 is lesser than 100，接着程序遇到 fallthrough 语句，因此继续对下一个 case 中的表达式求值并与 true 做匹配，结果仍然是 true，因此打印：75 is lesser than 200。最后的输出如下：

```go
75 is lesser than 100 
75 is lesser than 200 
```

`fallthrough` 必须是 case 语句块中的最后一条语句。如果它出现在语句块的中间，编译器将会报错：fallthrough statement out of place。

## Type Switch 的基本用法

Type Switch 是 Go 语言中一种特殊的 switch 语句，它比较的是类型而不是具体的值。它判断某个接口变量的类型，然后根据具体类型再做相应处理。注意，在 Type Switch 语句的 case 子句中不能使用fallthrough。

```go
switch x.(type) {
case Type1:
    doSomeThingWithType1()
case Type2:
    doSomeThingWithType2()
default:
    doSomeDefaultThing()
}
```
其中，x必须是一个接口类型的变量，而所有的case语句后面跟的类型必须实现了x的接口类型。

为了便于理解，我们可以结合下面这个例子来看:

```go
type Animal interface {
    shout() string
}
type Dog struct {}
func (self Dog) shout() string {
    return fmt.Sprintf("wang wang")
}
type Cat struct {}
func (self Cat) shout() string {
    return fmt.Sprintf("miao miao")
}
func main() {
    var animal Animal = Dog{}
 
    switch animal.(type) {
    case Dog:
        fmt.Println("animal'type is Dog")
    case Cat:
        fmt.Println("animal'type is Cat")
    }
}
```

在上面的例子中，Cat和Dog类型都实现了接口Animal，所以它们可以跟在case语句后面，判断接口变量animal是否是对应的类型。

## 在Switch的语句表达式中声明变量

如果我们不仅想要判断某个接口变量的类型，还想要获得其类型转换后的值的话，我们可以在 Switch 的语句表达式中声明一个变量来获得这个值。

其用法如下所示:

```go
type Animal interface {
    shout() string
}
 
type Dog struct {
    name string
}
 
func (self Dog) shout() string {
    return fmt.Sprintf("wang wang")
}
 
type Cat struct {
    name string
}
 
func (self Cat) shout() string {
    return fmt.Sprintf("miao miao")
}
 
type Tiger struct {
    name string
}
 
func (self Tiger) shout() string {
    return fmt.Sprintf("hou hou")
}
 
func main() {
    // var animal Animal = Tiger{}
    // var animal Animal  // 验证 case nil
    // var animal Animal = Wolf{} // 验证 default
    var animal Animal = Dog{}
 
    switch a := animal.(type) {
    case nil: // a的类型是 Animal
        fmt.Println("nil", a)
    case Dog, Cat: // a的类型是 Animal
        fmt.Println(a) // 输出 {}
        // fmt.Println(a.name) 这里会报错，因为 Animal 类型没有成员name
    case Tiger: // a的类型是 Tiger
        fmt.Println(a.shout(), a.name) // 这里可以直接取出 name 成员
    default: // a的类型是 Animal
        fmt.Println("default", reflect.TypeOf(a), a)
    }
}
```

在上述代码中，我们可以看到`a := animal.(type)`语句隐式地为每个case子句声明了一个变量a。

变量a类型的判定规则如下:

+ 如果case后面跟着一个类型，那么变量a在这个case子句中就是这个类型。例如在case Tiger子句中a的类型就是Tiger
+ 如果case后面跟着多个类型，那么变量a的类型就是接口变量animal的类型，例如在case Dog, Cat子句中a的类型就是Animal
+ 如果case后面跟着nil，那么变量a的类型就是接口变量animal的类型Animal，通常这种子句用来判断未赋值的接口变量
+ default子句中变量a的类型是接口变量animal的类型

为了更好地理解上述规则，我们可以用if语句和类型断言来重写这个switch语句，如下所示：

```go
v := animal   // animal 只会被求值一次
if v == nil { // case nil 子句
    a := v
    fmt.Println("nil", a)
} else if a, isTiger := v.(Tiger); isTiger { // case Tiger 子句
    fmt.Println(a.shout(), a.name)
} else {
    _, isDog := v.(Dog)
    _, isCat := v.(Cat)
    if isDog || isCat { // case Dog, Cat 子句
        a := v
        fmt.Println(a)
        // fmt.Println(a.name)
    } else { // default 子句
        a := v
        fmt.Println("default", reflect.TypeOf(a), a)
    }
}
```