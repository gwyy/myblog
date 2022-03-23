本文从源码角度学习 golang map的一些操作，和对应的源码分析。

Golang的map使用哈希表作为底层实现，一个哈希表里可以有多个哈希表节点，也即bucket，而每个bucket就保存了map中的一个或一组键值对。

# 声明和初始化

golang中的map声明非常简单，我们用map关键字表示声明一个map，然后在方括号内填上key的类型，方括号外填上value的类型。

```go
var m map[string] int
```

这样我们就声明好了一个map。

但是要注意，这样声明得到的是一个空的map，**map的零值是nil**，可以理解成空指针。所以我们不能直接去操作这个m，否则会得到一个panic。

```go
panic: assignment to entry in nil map
```

我们声明了一个map之后，想要使用它还需要对它进行**初始化**。使用它的方法也很简单，就是使用make方法创建出一个实例来。它的用法和之前通过make创建元组非常类似：

```go
m = make(map[string] int)

// 我们还可以指定创建出来的map的存储能力的大小
m = make(map[string] int, 100)
//我们也可以在声明的时候把初始化也写上：
var m = map[string] int {"abc": 3, "ccd": 4}
//当然也可以通过赋值运算符，直接make出一个空的map来：
m := make(map[string] int)
```
初始化map的时候可以传一个hint容量，（当 hint 大于等于 8 ）第一次初始化 map 时，就会通过调用 makeBucketArray 对 buckets 进行分配。因此我们常常会说，在初始化时指定一个适当大小的容量。能够提升性能。

若该容量过少，而新增的键值对又很多。就会导致频繁的分配 buckets，进行扩容迁移等 rehash 动作。最终结果就是性能直接的下降。


## 增删改查

### 添加元素

首先是map的添加元素。map的添加元素直接用方括号赋值即可：

```go
m["abc"] = 4
```

同样，我们需要保证这里的m经过初始化，否则也会包nil的panic。如果key值在map当中已经存在，那么会自动替换掉原本的key。也就是说map的更新和添加元素都是一样的，都是通过这种方式。如果不存在就是添加，否则则是更新。

### 删除元素

删除元素也很简单，和Python当中类似，通过**delete关键字删除**。

```go
delete(m, "abc")
```

当我们删除key的时候，如果是其他的语言，我们需要判断这个key值是否存在，否则的话不能删除，或者是会引起异常。在golang当中并不会，对这点做了优化。如果要删除的key值原本就不在map当中，那么当我们调用了delete之后，**什么也不会发生**。但是有一点，必须要保证传入的map不为nil，否则也会引起panic。

### 查找元素

如果是其他语言，我们直接访问一个不存在的key是会抛出异常的，但是在golang当中不会触发panic，因为它会额外返回一个bool类型的元素表示元素是否查找到。所以我们可以同时用两个变量去接收，如果第二个变量为True的话，就说明查找成功了。

进一步，我们还可以将这个逻辑和if的初始化操作合在一起：

```fsharp
if val, ok := m["1234"]; ok {
    fmt.Println(val)
}
```

这里的ok就表示查找是否成功，这也是golang当中map查找的惯用写法。



# map源码分析

## hmap数据结构
前面说了 map 的使用方法，Go 语言采用的是哈希查找表，并且使用链表解决哈希冲突。

map数据结构由`runtime/map.go/hmap`定义:

在源码中，表示 map 的结构体是 hmap，它是 hashmap 的“缩写”：

```go
// A header for a Go map.
type hmap struct {
	// Note: the format of the hmap is also encoded in cmd/compile/internal/gc/reflect.go.
	// Make sure this stays in sync with the compiler's definitio
	// 代表哈希表中的元素个数，调用len(map)时，返回的就是该字段值。
	count     int // # live cells == size of map.  Must be first (used by len() builtin)
	flags     uint8 //表示哈希表的标记 1表示buckets正在被使用 2表示oldbuckets正在被使用 4表示哈希正在被写入 8表示哈希是等量扩容
    // 桶的数量2^B   buckets（桶）的对数log_2（哈希表元素数量最大可达到装载因子*2^B）
	B         uint8  // log_2 of # of buckets (can hold up to loadFactor * 2^B items) B表示2的B次方系数表示,如B是5,那么桶的数量就有2^5个
	//// 溢出桶的大概数量。
	noverflow uint16 // approximate number of overflow buckets; see incrnoverflow for details 溢出桶数量统计
	hash0     uint32 // hash seed  // 哈希因子,用于计算出hash值
    // 指向buckets数组的指针，数组大小为2^B，如果元素个数为0，它为nil。
	buckets    unsafe.Pointer // array of 2^B Buckets. may be nil if count==0. 2^B的桶
	//// 如果发生扩容，oldbuckets是指向老的buckets数组的指针，老的buckets数组大小是新的buckets的1/2。非扩容状态下，它为nil。
	oldbuckets unsafe.Pointer // previous bucket array of half the size, non-nil only when growing 扩容时用于保存之前的buckets
	// // 表示扩容进度，小于此地址的buckets代表已搬迁完成。
	nevacuate  uintptr        // progress counter for evacuation (buckets less than this have been evacuated) 扩容之后数据迁移的计数器,记录下次迁移的位置   
	// 这个字段是为了优化GC扫描而设计的。当key和value均不包含指针，并且都可以inline时使用。extra是指向mapextra类型的指针。
	extra *mapextra // optional fields  额外的map字段,存储溢出桶信息
}
//哈希表结构体溢出桶信息：
// mapextra holds fields that are not present on all maps.
type mapextra struct {
// 如果 key 和 value 都不包含指针，并且可以被 inline(<=128 字节)
// 就使用 hmap的extra字段 来存储 overflow buckets，这样可以避免 GC 扫描整个 map
// 然而 bmap.overflow 也是个指针。这时候我们只能把这些 overflow 的指针
// 都放在 hmap.extra.overflow 和 hmap.extra.oldoverflow 中了
// overflow 包含的是 hmap.buckets 的 overflow 的 buckets
// oldoverflow 包含扩容时的 hmap.oldbuckets 的 overflow 的 bucket
	overflow    *[]*bmap //所有的溢出桶数据
	oldoverflow *[]*bmap //所有旧溢出桶数据

	//  指向空闲的 overflow bucket 的指针
	// nextOverflow holds a pointer to a free overflow bucket.
	nextOverflow *bmap //指向下一个溢出桶
}
```

说明一下，`B` 是 buckets 数组的长度的对数，也就是说 buckets 数组的长度就是 2^B。bucket 里面存储了 key 和 value。

buckets 是一个指针，最终它指向的是一个结构体：

```go
type bmap struct {
	tophash [bucketCnt]uint8
}
```

但这只是表面(src/runtime/hashmap.go)的结构，编译期间会给它加料，动态地创建一个新的结构：

```go
type bmap struct {
    topbits  [8]uint8
    keys     [8]keytype
    values   [8]valuetype
    pad      uintptr
    overflow uintptr
}
```

`bmap` 就是我们常说的“桶”，桶里面会最多装 8 个 key，这些 key 之所以会落入同一个桶，是因为它们经过哈希计算后，哈希结果是“一类”的。在桶内，又会根据 key 计算出来的 hash 值的高 8 位来决定 key 到底落入桶内的哪个位置（一个桶内最多有8个位置）。

来一个整体的图：

![hmap](https://img1.liangtian.me/myblog/imgs/go-map1.png?x-oss-process=style/small)

bmap 是存放 k-v 的地方，我们把视角拉近，仔细看 bmap 的内部组成。
![hmap](https://img1.liangtian.me/myblog/imgs/go-map2.png?x-oss-process=style/small)

上图就是 bucket 的内存模型，HOB Hash 指的就是 top hash。 注意到 key 和 value 是各自放在一起的，并不是 key/value/key/value/... 这样的形式。源码里说明这样的好处是在某些情况下可以省略掉 padding 字段，节省内存空间。

例如，有这样一个类型的 map：
```go
map[int64]int8
```
如果按照 key/value/key/value/... 这样的模式存储，那在每一个 key/value 对之后都要额外 padding 7 个字节；而将所有的 key，value 分别绑定到一起，这种形式 key/key/.../value/value/...，则只需要在最后添加 padding。

每个 bucket 设计成最多只能放 8 个 key-value 对，如果有第 9 个 key-value 落入当前的 bucket，那就需要再构建一个 bucket ，通过 overflow 指针连接起来。

## 创建map方法
对于不指定初始化大小，和初始化值hint<=8（bucketCnt）时，go会调用makemap_small函数（源码位置src/runtime/map.go），并直接从堆上进行分配。
```go
func makemap_small() *hmap {
    h := new(hmap)
    h.hash0 = fastrand()
    return h
}
```
当hint>8时，则调用makemap函数

```go
// 如果编译器认为map和第一个bucket可以直接创建在栈上，h和bucket可能都是非空
// 如果h != nil，那么map可以直接在h中创建
// 如果h.buckets != nil，那么h指向的bucket可以作为map的第一个bucket使用
func makemap(t *maptype, hint int, h *hmap) *hmap {
// math.MulUintptr返回hint与t.bucket.size的乘积，并判断该乘积是否溢出。
    mem, overflow := math.MulUintptr(uintptr(hint), t.bucket.size)
// maxAlloc的值，根据平台系统的差异而不同，具体计算方式参照src/runtime/malloc.go
	if overflow || mem > maxAlloc {
		hint = 0
	}
	// initialize Hmap
	if h == nil {
		h = new(hmap)
	}
    // 通过fastrand得到哈希种子
	h.hash0 = fastrand()
	// Find the size parameter B which will hold the requested # of elements.
	// For hint < 0 overLoadFactor returns false since hint < bucketCnt.
	// 根据输入的元素个数hint，找到能装下这些元素的B值
	B := uint8(0)
	for overLoadFactor(hint, B) {
		B++
	}
	h.B = B

	// allocate initial hash table
	// if B == 0, the buckets field is allocated lazily later (in mapassign)
	// If hint is large zeroing this memory could take a while.
	// 分配初始哈希表
	// 如果B为0，那么buckets字段后续会在mapassign方法中lazily分配
	if h.B != 0 {
		var nextOverflow *bmap
		// makeBucketArray创建一个map的底层保存buckets的数组，它最少会分配h.B^2的大小。
		h.buckets, nextOverflow = makeBucketArray(t, h.B, nil)
		if nextOverflow != nil {
			h.extra = new(mapextra)
			h.extra.nextOverflow = nextOverflow
		}
	}
	return h
}
```
分配buckets数组的makeBucketArray函数

```go
// makeBucket为map创建用于保存buckets的数组。
func makeBucketArray(t *maptype, b uint8, dirtyalloc unsafe.Pointer) (buckets unsafe.Pointer, nextOverflow *bmap) {
    base := bucketShift(b)
    nbuckets := base
  // 对于小的b值（小于4），即桶的数量小于16时，使用溢出桶的可能性很小。对于此情况，就避免计算开销。
    if b >= 4 {
    // 当桶的数量大于等于16个时，正常情况下就会额外创建2^(b-4)个溢出桶
        nbuckets += bucketShift(b - 4)
        sz := t.bucket.size * nbuckets
        up := roundupsize(sz)
        if up != sz {
            nbuckets = up / t.bucket.size
        }
    }

 // 这里，dirtyalloc分两种情况。如果它为nil，则会分配一个新的底层数组。如果它不为nil，则它指向的是曾经分配过的底层数组，该底层数组是由之前同样的t和b参数通过makeBucketArray分配的，如果数组不为空，需要把该数组之前的数据清空并复用。
    if dirtyalloc == nil {
        buckets = newarray(t.bucket, int(nbuckets))
    } else {
        buckets = dirtyalloc
        size := t.bucket.size * nbuckets
        if t.bucket.ptrdata != 0 {
            memclrHasPointers(buckets, size)
        } else {
            memclrNoHeapPointers(buckets, size)
        }
}

  // 即b大于等于4的情况下，会预分配一些溢出桶。
  // 为了把跟踪这些溢出桶的开销降至最低，使用了以下约定：
  // 如果预分配的溢出桶的overflow指针为nil，那么可以通过指针碰撞（bumping the pointer）获得更多可用桶。
  // （关于指针碰撞：假设内存是绝对规整的，所有用过的内存都放在一边，空闲的内存放在另一边，中间放着一个指针作为分界点的指示器，那所分配内存就仅仅是把那个指针向空闲空间那边挪动一段与对象大小相等的距离，这种分配方式称为“指针碰撞”）
  // 对于最后一个溢出桶，需要一个安全的非nil指针指向它。
    if base != nbuckets {
        nextOverflow = (*bmap)(add(buckets, base*uintptr(t.bucketsize)))
        last := (*bmap)(add(buckets, (nbuckets-1)*uintptr(t.bucketsize)))
        last.setoverflow(t, (*bmap)(buckets))
    }
    return buckets, nextOverflow
}
```
根据上述代码，我们能确定在正常情况下，正常桶和溢出桶在内存中的存储空间是连续的，只是被 hmap 中的不同字段引用而已。

## key的定位

key 经过哈希计算后得到哈希值，共 64 个 bit 位，计算它到底要落在哪个桶时，只会用到最后 B 个 bit 位。还记得前面提到过的 B 吗？如果 B = 5，那么桶的数量，也就是 buckets 数组的长度是 2^5 = 32。

例如，现在有一个 key 经过哈希函数计算后，得到的哈希结果是：

```go
 10010111 | 000011110110110010001111001010100010010110010101010 │ 01010
```
用最后的 5 个 bit 位，也就是 01010，值为 10，也就是 10 号桶。这个操作实际上就是取余操作，但是取余开销太大，所以代码实现上用的位操作代替。

再用哈希值的高 8 位，找到此 key 在 bucket 中的位置，这是在寻找已有的 key。最开始桶内还没有 key，新加入的 key 会找到第一个空位，放入。

buckets 编号就是桶编号，当两个不同的 key 落在同一个桶中，也就是发生了哈希冲突。冲突的解决手段是用链表法：在 bucket 中，从前往后找到第一个空位。这样，在查找某个 key 时，先找到对应的桶，再去遍历 bucket 中的 key。

以下是tophash的实现代码。
```go
func tophash(hash uintptr) uint8 {
    top := uint8(hash >> (sys.PtrSize*8 - 8))
    if top < minTopHash {
        top += minTopHash
    }
    return top
}
```
![hmap](https://img1.liangtian.me/myblog/imgs/go-map3.png?x-oss-process=style/small)

上图中，假定 B = 5，所以 bucket 总数就是 2^5 = 32。首先计算出待查找 key 的哈希，使用低 5 位 00110，找到对应的 6 号 bucket，使用高 8 位 10010111，对应十进制 151，在 6 号 bucket 中寻找 tophash 值（HOB hash）为 151 的 key，找到了 2 号槽位，这样整个查找过程就结束了。

如果在 bucket 中没找到，并且 overflow 不为空，还要继续去 overflow bucket 中寻找，直到找到或是所有的 key 槽位都找遍了，包括所有的 overflow bucket。

对于map的元素查找，其源码实现如下
```go
func mapaccess1(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer {
  // 如果开启了竞态检测 -race
    if raceenabled && h != nil {
        callerpc := getcallerpc()
        pc := funcPC(mapaccess1)
        racereadpc(unsafe.Pointer(h), callerpc, pc)
        raceReadObjectPC(t.key, key, callerpc, pc)
    }
  // 如果开启了memory sanitizer -msan
    if msanenabled && h != nil {
        msanread(key, t.key.size)
    }
  // 如果map为空或者元素个数为0，返回零值
    if h == nil || h.count == 0 {
        if t.hashMightPanic() {
            t.hasher(key, 0) // see issue 23734
        }
        return unsafe.Pointer(&zeroVal[0])
    }
  // 注意，这里是按位与操作
  // 当h.flags对应的值为hashWriting（代表有其他goroutine正在往map中写key）时，那么位计算的结果不为0，因此抛出以下错误。
  // 这也表明，go的map是非并发安全的
    if h.flags&hashWriting != 0 {
        throw("concurrent map read and map write")
    }
  // 不同类型的key，会使用不同的hash算法，可详见src/runtime/alg.go中typehash函数中的逻辑
    hash := t.hasher(key, uintptr(h.hash0))
    m := bucketMask(h.B)
  // 按位与操作，找到对应的bucket
    b := (*bmap)(add(h.buckets, (hash&m)*uintptr(t.bucketsize)))
  // 如果oldbuckets不为空，那么证明map发生了扩容
  // 如果有扩容发生，老的buckets中的数据可能还未搬迁至新的buckets里
  // 所以需要先在老的buckets中找
    if c := h.oldbuckets; c != nil {
        if !h.sameSizeGrow() {
            m >>= 1
        }
        oldb := (*bmap)(add(c, (hash&m)*uintptr(t.bucketsize)))
    // 如果在oldbuckets中tophash[0]的值，为evacuatedX、evacuatedY，evacuatedEmpty其中之一
    // 则evacuated()返回为true，代表搬迁完成。
    // 因此，只有当搬迁未完成时，才会从此oldbucket中遍历
        if !evacuated(oldb) {
            b = oldb
        }
    }
  // 取出当前key值的tophash值
    top := tophash(hash)
  // 以下是查找的核心逻辑
  // 双重循环遍历：外层循环是从桶到溢出桶遍历；内层是桶中的cell遍历
  // 跳出循环的条件有三种：第一种是已经找到key值；第二种是当前桶再无溢出桶；
  // 第三种是当前桶中有cell位的tophash值是emptyRest，这个值在前面解释过，它代表此时的桶后面的cell还未利用，所以无需再继续遍历。
bucketloop:
    for ; b != nil; b = b.overflow(t) {
        for i := uintptr(0); i < bucketCnt; i++ {
      // 判断tophash值是否相等
            if b.tophash[i] != top {
                if b.tophash[i] == emptyRest {
                    break bucketloop
                }
                continue
      }
      // 因为在bucket中key是用连续的存储空间存储的，因此可以通过bucket地址+数据偏移量（bmap结构体的大小）+ keysize的大小，得到k的地址
      // 同理，value的地址也是相似的计算方法，只是再要加上8个keysize的内存地址
            k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
            if t.indirectkey() {
                k = *((*unsafe.Pointer)(k))
            }
      // 判断key是否相等
            if t.key.equal(key, k) {
                e := add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
                if t.indirectelem() {
                    e = *((*unsafe.Pointer)(e))
                }
                return e
            }
        }
    }
  // 所有的bucket都未找到，则返回零值
    return unsafe.Pointer(&zeroVal[0])
}
```
## map元素查找
map的元素查找，对应go代码有两种形式
```go
// 形式一
v := m[k]
// 形式二
v, ok := m[k]
```
形式一的代码实现，就是上述的mapaccess1方法。此外，在源码中还有个mapaccess2方法，它的函数签名如下。
```go
func mapaccess2(t *maptype, h *hmap, key unsafe.Pointer) (unsafe.Pointer, bool) {}
```
与mapaccess1相比，mapaccess2多了一个bool类型的返回值，它代表的是是否在map中找到了对应的key。因为和mapaccess1基本一致，所以详细代码就不再贴出。

同时，源码中还有mapaccessK方法，它的函数签名如下。
```go
func mapaccessK(t *maptype, h *hmap, key unsafe.Pointer) (unsafe.Pointer, unsafe.Pointer) {}
```
与mapaccess1相比，mapaccessK同时返回了key和value，其代码逻辑也一致。

## 赋值key

对于写入key的逻辑，其源码实现如下：
```go
func mapassign(t *maptype, h *hmap, key unsafe.Pointer) unsafe.Pointer {
  // 如果h是空指针，赋值会引起panic
  // 例如以下语句
  // var m map[string]int
    // m["k"] = 1
    if h == nil {
        panic(plainError("assignment to entry in nil map"))
    }
  // 如果开启了竞态检测 -race
    if raceenabled {
        callerpc := getcallerpc()
        pc := funcPC(mapassign)
        racewritepc(unsafe.Pointer(h), callerpc, pc)
        raceReadObjectPC(t.key, key, callerpc, pc)
    }
  // 如果开启了memory sanitizer -msan
    if msanenabled {
        msanread(key, t.key.size)
    }
  // 有其他goroutine正在往map中写key，会抛出以下错误
    if h.flags&hashWriting != 0 {
        throw("concurrent map writes")
    }
  // 通过key和哈希种子，算出对应哈希值
    hash := t.hasher(key, uintptr(h.hash0))

  // 将flags的值与hashWriting做按位或运算
  // 因为在当前goroutine可能还未完成key的写入，再次调用t.hasher会发生panic。
    h.flags ^= hashWriting

    if h.buckets == nil {
        h.buckets = newobject(t.bucket) // newarray(t.bucket, 1)
}

again:
  // bucketMask返回值是2的B次方减1
  // 因此，通过hash值与bucketMask返回值做按位与操作，返回的在buckets数组中的第几号桶
    bucket := hash & bucketMask(h.B)
  // 如果map正在搬迁（即h.oldbuckets != nil）中,则先进行搬迁工作。
    if h.growing() {
        growWork(t, h, bucket)
    }
  // 计算出上面求出的第几号bucket的内存位置
  // post = start + bucketNumber * bucketsize
    b := (*bmap)(unsafe.Pointer(uintptr(h.buckets) + bucket*uintptr(t.bucketsize)))
    top := tophash(hash)

    var inserti *uint8
    var insertk unsafe.Pointer
    var elem unsafe.Pointer
bucketloop:
    for {
    // 遍历桶中的8个cell
        for i := uintptr(0); i < bucketCnt; i++ {
      // 这里分两种情况，第一种情况是cell位的tophash值和当前tophash值不相等
      // 在 b.tophash[i] != top 的情况下
      // 理论上有可能会是一个空槽位
      // 一般情况下 map 的槽位分布是这样的，e 表示 empty:
      // [h0][h1][h2][h3][h4][e][e][e]
      // 但在执行过 delete 操作时，可能会变成这样:
      // [h0][h1][e][e][h5][e][e][e]
      // 所以如果再插入的话，会尽量往前面的位置插
      // [h0][h1][e][e][h5][e][e][e]
      //          ^
      //          ^
      //       这个位置
      // 所以在循环的时候还要顺便把前面的空位置先记下来
      // 因为有可能在后面会找到相等的key，也可能找不到相等的key
            if b.tophash[i] != top {
        // 如果cell位为空，那么就可以在对应位置进行插入
                if isEmpty(b.tophash[i]) && inserti == nil {
                    inserti = &b.tophash[i]
                    insertk = add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
                    elem = add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
                }
                if b.tophash[i] == emptyRest {
                    break bucketloop
                }
                continue
            }
      // 第二种情况是cell位的tophash值和当前的tophash值相等
            k := add(unsafe.Pointer(b), dataOffset+i*uintptr(t.keysize))
            if t.indirectkey() {
                k = *((*unsafe.Pointer)(k))
            }
      // 注意，即使当前cell位的tophash值相等，不一定它对应的key也是相等的，所以还要做一个key值判断
            if !t.key.equal(key, k) {
                continue
            }
            // 如果已经有该key了，就更新它
            if t.needkeyupdate() {
                typedmemmove(t.key, k, key)
            }
      // 这里获取到了要插入key对应的value的内存地址
      // pos = start + dataOffset + 8*keysize + i*elemsize
            elem = add(unsafe.Pointer(b), dataOffset+bucketCnt*uintptr(t.keysize)+i*uintptr(t.elemsize))
      // 如果顺利到这，就直接跳到done的结束逻辑中去
            goto done
        }
    // 如果桶中的8个cell遍历完，还未找到对应的空cell或覆盖cell，那么就进入它的溢出桶中去遍历
        ovf := b.overflow(t)
    // 如果连溢出桶中都没有找到合适的cell，跳出循环。
        if ovf == nil {
            break
        }
        b = ovf
    }

    // 在已有的桶和溢出桶中都未找到合适的cell供key写入，那么有可能会触发以下两种情况
  // 情况一：
  // 判断当前map的装载因子是否达到设定的6.5阈值，或者当前map的溢出桶数量是否过多。如果存在这两种情况之一，则进行扩容操作。
  // hashGrow()实际并未完成扩容，对哈希表数据的搬迁（复制）操作是通过growWork()来完成的。
  // 重新跳入again逻辑，在进行完growWork()操作后，再次遍历新的桶。
    if !h.growing() && (overLoadFactor(h.count+1, h.B) || tooManyOverflowBuckets(h.noverflow, h.B)) {
        hashGrow(t, h)
        goto again // Growing the table invalidates everything, so try again
    }

  // 情况二：
// 在不满足情况一的条件下，会为当前桶再新建溢出桶，并将tophash，key插入到新建溢出桶的对应内存的0号位置
    if inserti == nil {
        // all current buckets are full, allocate a new one.
        newb := h.newoverflow(t, b)
        inserti = &newb.tophash[0]
        insertk = add(unsafe.Pointer(newb), dataOffset)
        elem = add(insertk, bucketCnt*uintptr(t.keysize))
    }

  // 在插入位置存入新的key和value
    if t.indirectkey() {
        kmem := newobject(t.key)
        *(*unsafe.Pointer)(insertk) = kmem
        insertk = kmem
    }
    if t.indirectelem() {
        vmem := newobject(t.elem)
        *(*unsafe.Pointer)(elem) = vmem
    }
    typedmemmove(t.key, insertk, key)
    *inserti = top
  // map中的key数量+1
    h.count++

done:
    if h.flags&hashWriting == 0 {
        throw("concurrent map writes")
    }
    h.flags &^= hashWriting
    if t.indirectelem() {
        elem = *((*unsafe.Pointer)(elem))
    }
    return elem
}
```
通过对mapassign的代码分析之后，发现该函数并没有将插入key对应的value写入对应的内存，而是返回了value应该插入的内存地址。为了弄清楚value写入内存的操作是发生在什么时候，分析如下map.go代码。
```go
package main

func main() {
m := make(map[int]int)
for i := 0; i < 100; i++ {
m[i] = 666
}
}
```

m[i] = 666对应的汇编代码
```go
$ go tool compile -S map.go
...
0x0098 00152 (map.go:6) LEAQ    type.map[int]int(SB), CX
0x009f 00159 (map.go:6) MOVQ    CX, (SP)
0x00a3 00163 (map.go:6) LEAQ    ""..autotmp_2+184(SP), DX
0x00ab 00171 (map.go:6) MOVQ    DX, 8(SP)
0x00b0 00176 (map.go:6) MOVQ    AX, 16(SP)
0x00b5 00181 (map.go:6) CALL    runtime.mapassign_fast64(SB) // 调用函数runtime.mapassign_fast64，该函数实质就是mapassign（上文示例源代码是该mapassign系列的通用逻辑）
0x00ba 00186 (map.go:6) MOVQ    24(SP), AX 24(SP), AX // 返回值，即 value 应该存放的内存地址
0x00bf 00191 (map.go:6) MOVQ    $666, (AX) // 把 666 放入该地址中
...
```
赋值的最后一步实际上是编译器额外生成的汇编指令来完成的，可见靠 runtime 有些工作是没有做完的。所以，在go中，编译器和 runtime 配合，才能完成一些复杂的工作。同时说明，在平时学习go的源代码实现时，必要时还需要看一些汇编代码。

## 遍历map
结论：迭代 map 的结果是无序的
```go
m := make(map[int]int)
for i := 0; i < 10; i++ {
    m[i] = i
}
for k, v := range m {
    fmt.Println(k, v)
}
```

运行以上代码，我们会发现每次输出顺序都是不同的。

map遍历的过程，是按序遍历bucket，同时按需遍历bucket中和其overflow bucket中的cell。但是map在扩容后，会发生key的搬迁，这造成原来落在一个bucket中的key，搬迁后，有可能会落到其他bucket中了，从这个角度看，遍历map的结果就不可能是按照原来的顺序了（详见下文的map扩容内容）。

但其实，go为了保证遍历map的结果是无序的，做了以下事情：map在遍历时，并不是从固定的0号bucket开始遍历的，每次遍历，都会从一个随机值序号的bucket，再从其中随机的cell开始遍历。然后再按照桶序遍历下去，直到回到起始桶结束。

![遍历](https://img1.liangtian.me/myblog/imgs/go-map1.jpg?x-oss-process=style/small)

上图的例子，是遍历一个处于未扩容状态的map。如果map正处于扩容状态时，需要先判断当前遍历bucket是否已经完成搬迁，如果数据还在老的bucket，那么就去老bucket中拿数据。

这里注释一下mapiterinit()中随机保证的关键代码
```go
// 生成随机数
r := uintptr(fastrand())
if h.B > 31-bucketCntBits {
   r += uintptr(fastrand()) << 31
}
// 决定了从哪个随机的bucket开始
it.startBucket = r & bucketMask(h.B)
// 决定了每个bucket中随机的cell的位置
it.offset = uint8(r >> h.B & (bucketCnt - 1))
```
# 总结

+ Go语言的map，底层是哈希表实现的，通过链地址法解决哈希冲突，它依赖的核心数据结构是数组加链表。

+ map中定义了2的B次方个桶，每个桶中能够容纳8个key。根据key的不同哈希值，将其散落到不同的桶中。哈希值的低位（哈希值的后B个bit位）决定桶序号，高位（哈希值的前8个bit位）标识同一个桶中的不同 key。

+ 当向桶中添加了很多 key，造成元素过多，超过了装载因子所设定的程度，或者多次增删操作，造成溢出桶过多，均会触发扩容。

+ 扩容分为增量扩容和等量扩容。增量扩容，会增加桶的个数（增加一倍），把原来一个桶中的 keys 被重新分配到两个桶中。等量扩容，不会更改桶的个数，只是会将桶中的数据变得紧凑。不管是增量扩容还是等量扩容，都需要创建新的桶数组，并不是原地操作的。

+ 扩容过程是渐进性的，主要是防止一次扩容需要搬迁的 key 数量过多，引发性能问题。触发扩容的时机是增加了新元素， 桶搬迁的时机则发生在赋值、删除期间，每次最多搬迁两个 桶。查找、赋值、删除的一个很核心的内容是如何定位到 key 所在的位置，需要重点理解。一旦理解，关于 map 的源码就可以看懂了。

+ 从map设计可以知道，它并不是一个并发安全的数据结构。同时对map进行读写时，程序很容易出错。因此，要想在并发情况下使用map，请加上锁（sync.Mutex或者sync.RwMutex）。其实，Go标准库中已经为我们实现了并发安全的map——sync.Map，我之前写过文章对它的实现进行讲解，详情可以查看公号：Golang技术分享——《深入理解sync.Map》一文。

# 使用建议
+ 遍历map的结果是无序的，在使用中，应该注意到该点。

+ 通过map的结构体可以知道，它其实是通过指针指向底层buckets数组。所以和slice一样，尽管go函数都是值传递，但是，当map作为参数被函数调用时，在函数内部对map的操作同样会影响到外部的map。

+ 另外，有个特殊的key值math.NaN，它每次生成的哈希值是不一样的，这会造成m[math.NaN]是拿不到值的，而且多次对它赋值，会让map中存在多个math.NaN的key。不过这个基本用不到，知道有这个特殊情况就可以了。


**可以边遍历边删除吗 ？**

map 并不是一个线程安全的数据结构。同时读写一个 map 是未定义的行为，如果被检测到，会直接 panic。

上面说的是发生在多个协程同时读写同一个 map 的情况下。 如果在同一个协程内边遍历边删除，并不会检测到同时读写，理论上是可以这样做的。但是，遍历的结果就可能不会是相同的了，有可能结果遍历结果集中包含了删除的 key，也有可能不包含，这取决于删除 key 的时间：是在遍历到 key 所在的 bucket 时刻前或者后。

一般而言，这可以通过读写锁来解决：sync.RWMutex。

读之前调用 RLock() 函数，读完之后调用 RUnlock() 函数解锁；写之前调用 Lock() 函数，写完之后，调用 Unlock() 解锁。

另外，sync.Map 是线程安全的 map，也可以使用。

**可以对map的元素取地址吗？**

无法对 map 的 key 或 value 进行取址。编译报错。
```go
./main.go:8:14: cannot take the address of m["qcrao"]
```
如果通过其他 hack 的方式，例如 unsafe.Pointer 等获取到了 key 或 value 的地址，也不能长期持有，因为一旦发生扩容，key 和 value 的位置就会改变，之前保存的地址也就失效了。

**如何比较两个map相等？**

直接将使用 map1 == map2 是错误的。这种写法只能比较 map 是否为 nil。只能是遍历map 的每个元素，比较元素是否都是深度相等。