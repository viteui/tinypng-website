# 无阻塞、高性能：将Rust的imagequant库带入Web前端

## 背景

本文记录了Png压缩库的调研过程，将优秀的imagequant Rust包编译成浏览器可用的WASM包，并通过Worker解决主线程阻塞的问题。

图片压缩一直是前端/客户端必须优化的问题之一，高质量低尺寸的文件能够提高响应速度，减少流量，目前不同规模的团队在不同场景可能有以下方式来解决这个问题：

- 服务端压缩：比如云对象存储 Cloudflare Images
- 代码自动压缩：比如前端脚手架压缩
- 手动压缩：比如Squoosh，TinyPng

因为压缩目前还是最主流的压缩方式，并且Squoosh png压缩效果不佳（包太旧了），于是想自己重新再编译一套最新的wasm。

## 相关术语

[squoosh](https://squoosh.app/)：Chrome团队一个开源的客户端图片压缩网站

[imagequant](https://crates.io/crates/imagequant)：一个处理png图像质量的库，可以减少图片的质量，本文用的是rust版本

[wasm-pack](https://github.com/rustwasm/wasm-pack?tab=readme-ov-file)：将rust打包成npm包的脚手架工具

[crates](https://crates.io/crates/imagequant)：一个rust lib下载平台，类似于npm

## WebAssembly的两种形态

首先简单介绍一下WebAssembly两种形态：

- 机器码格式
- 文本格式

这种文本形式更类似于处理器的汇编指令,因为WebAssembly本身是一门语言，一个小小的实例：

```Assembly
(module
  (table 2 anyfunc)
  (func $f1 (result i32)
    i32.const 42)
  (func $f2 (result i32)
    i32.const 13)
  (elem (i32.const 0) $f1 $f2)
  (type $return_i32 (func (result i32)))
  (func (export "callByIndex") (param $i i32) (result i32)
    local.get $i
    call_indirect $return_i32)
)
```

一般很少有人直接写文本格式，而是通过其他语言、或者是现存lib来编译成浏览器可用的wasm，这样很多客户端的计算模块只需简单处理都能很快转译成WASM在浏览器使用的模块，极大丰富了浏览器的使用场景。

接着我们先从一个入门实例开始，逐步到自己动手编译一个Rust模块。

![img](https://cdn.jsdelivr.net/gh/viteui/viteui.github.io@web-image/web/image/202410050124657.(null))

[Rust在WebAssembly中的简单使用](https://web.wcrane.cn/251-技术拓展/5-Rust/Rust学习/200-Rust在WebAssembly中的简单使用.html)

## imagequant打包成npm包

### 压缩库选型

简单聊一下为什么选择imagequant，这也是调研得出来的结论，squoosh是开发者使用最多的一个的一个开源图片图片的网站（3年未更新），因此对于其他格式的压缩，可以部分copy其中一些比较优异的压缩库，不满意的部分比如png的可以自己编译wasm。

| 图片类型 | 压缩库         | 结论                                                         |
| -------- | -------------- | ------------------------------------------------------------ |
| PNG      | oxiPNG         | squoosh使用的png压缩库，压缩率很一般，15-25%左右             |
| PNG      | imagequant     | https://crates.io/crates/imagequant 压缩效果≈70% squoosh编译出来的wasm太老了(v2.12.1)， 需要自己再编译一次,最新的是（v4.3.0） |
| JPEG     | mozJPEG        | https://github.com/mozilla/mozjpeg 压缩效果≈80%              |
| WEBP     | libwebp        | https://github.com/webmproject/libwebp 压缩效果>90%          |
| SVG      | libsvgo        | https://github.com/svg/svgo 压缩效果10%~30% 原库svgo只支持node环境，libsvgo提供了浏览器的支持模式 |
| AVIF     | avif-serialize | https://github.com/packurl/wasm_avif 压缩效果>90%,但当前的兼容性差 squoosh使用的也比较旧， 且Figma不支持SharedArrayBuffer 重新编译了最新的avif-serialize |

**压缩效果是如何鉴别的？**

纯肉眼拖动观察肯定不够客观全面，所以我用了多张色彩对鲜明、和业务相关图片进行测验。

图片对比工具： https://www.diffchecker.com/image-compare/

![img](https://cdn.jsdelivr.net/gh/viteui/viteui.github.io@web-image/web/image/202410052111513.(null))

![img](https://cdn.jsdelivr.net/gh/viteui/viteui.github.io@web-image/web/image/202410052110784.(null))

## PNG压缩打包

前面说到，sqoosh的oxipng压缩效果差、imagequant版本老，因此这里需要自己手动来打包

首先需要找到imagequant的rust库（crates类似npm）

https://crates.io/crates/imagequant

然后将依赖加入到Cargo.toml (这个类似package.json)

```js
[package]
name = "tinypng-lib-wasm"
version = "1.0.50"
edition = "2021"
author = ["wacrne"]
description = "TinyPNG Rust WASM Library"
license = "MIT"
keywords = []

[lib]
crate-type = ["cdylib", "rlib"]

[dependencies]
imagequant = { version = "4.2.0", default-features = false }
wasm-bindgen = "0.2.84"

# The `console_error_panic_hook` crate provides better debugging of panics by
# logging them with `console.error`. This is great for development, but requires
# all the `std::fmt` and `std::panicking` infrastructure, so isn't great for
# code size when deploying.
console_error_panic_hook = { version = "0.1.7", optional = true }
lodepng = "3.7.2"
```

然后编写部分导出代码，将处理图片的函数暴露给js调用

```js
#[wasm_bindgen]
impl Imagequant {
    #[wasm_bindgen(constructor)]
    pub fn new() -> Imagequant {
        Imagequant {
            instance: imagequant::new(),
        }
    }

    /// Make an image from RGBA pixels.
    /// Use 0.0 for gamma if the image is sRGB (most images are).
    pub fn new_image(data: Vec<u8>, width: usize, height: usize, gamma: f64) -> ImagequantImage {
        ImagequantImage::new(data, width, height, gamma)
    }
 //. 省略
}
```

打包生成npm package

![img](https://cdn.jsdelivr.net/gh/viteui/viteui.github.io@web-image/web/image/202410052111127.(null))

可以先从d.ts中看生成的代码如何调用，从文件中看到需要输入uint8Array和图片尺寸大小，于是我们可以这样调用：

```js
import { Imagequant, ImagequantImage } from 'tinypng-lib-wasm'

// 获取图片元信息
const { width, height, imageData } = await this.getImageBitInfo()
// 将 Uint8Array 数据从发给 Imagequant/WASM
const uint8Array = new Uint8Array(imageData.data.buffer)
const image = new ImagequantImage(uint8Array, width, height, 0)
const instance = new Imagequant()
// 配置压缩质量
instance.set_quality(30, 85)
// 启动压缩
const output = instance.process(image)

const outputBlob = new Blob([output.buffer], { type: 'image/png' })

```
```js
// 获取图片信息：宽、高、像素数据、图片大小
const getImageBitInfo = (file) => {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();

    // 创建一个 Image 对象
    const img = new Image();
    img.src = URL.createObjectURL(file);

    img.onload = () => {
      // 创建一个 canvas 元素
      const canvas = document.createElement('canvas');
      canvas.width = img.width;
      canvas.height = img.height;
      const ctx = canvas.getContext('2d');

      if (!ctx) {
        reject(new Error('无法获取 canvas 上下文'));
        return;
      }

      // 将图像绘制到 canvas 上
      ctx.drawImage(img, 0, 0);

      // 获取 ImageData
      const imageData = ctx.getImageData(0, 0, img.width, img.height);
      const data = imageData.data; // Uint8ClampedArray

      // 将 Uint8ClampedArray 转换为普通的 Uint8Array
      const buffer = new Uint8Array(data).buffer;

      // 确保缓冲区长度是 width * height * 4
      const expectedLength = img.width * img.height * 4;
      if (buffer.byteLength !== expectedLength) {
        reject(new Error(`缓冲区长度不匹配：期望 ${expectedLength} 字节，但得到 ${buffer.byteLength} 字节`));
        return;
      }

      resolve({
        buffer,
        width: img.width,
        height: img.height,
        size: file.size
      });

      // 释放对象 URL
      URL.revokeObjectURL(img.src);
    };

    img.onerror = () => {
      reject(new Error('图片加载失败'));
      URL.revokeObjectURL(img.src);
    };
  });
};
```

演示一下，压缩效果还不错，对于质量，还可以调整相关的参数。目前的参数设置为 `instance.set_quality(35, 88);`

压缩效果可以媲美tinify。

![img](https://cdn.jsdelivr.net/gh/viteui/viteui.github.io@web-image/web/image/202410050124857.(null))

压缩为原来的 27.6% （-62.4%）

tinify压缩效果（-61%）

![img](https://cdn.jsdelivr.net/gh/viteui/viteui.github.io@web-image/web/image/202410052110603.(null))

## 其他压缩库打包

其他库squoosh比如webp、jpg、avif已经帮忙打包好了，svg有现成的npm库，因此较为简单。

## 使用Worker避免阻塞js主线程

在压缩大图的时候，发现浏览器有点卡，周围的按钮的动效都无法正常运行，点也点不动。这是因为我们如果直接调用wasm会直接阻塞js主线程，既然是计算密集型的工作，这个时候就只能拿出非常适合这种场景的特性了：Worker。

![img](https://cdn.jsdelivr.net/gh/viteui/viteui.github.io@web-image/web/image/202410050124455.(null))

先实现一下woker中需要执行的代码，他完成了2件事情

- 在worker中执行压缩任务
- 监听主线程发送的文件，传输文件到主线程

### 使用步骤

1. webpack项目中安装`worker-loader`

```sh
npm install worker-loader
```



2. 在`webpack.config.js`中配置

```js
module.exports = {
  // ...
  module: {
    rules: [
      {
        test: /\.worker\.js$/,
        use: { loader: 'worker-loader' },
      },
    ],
  },
};
```



3. 定义`imageWorker.worker.js`

```js
// imageWorker.worker.js
import TinyPNG from 'tinypng-lib';

self.onmessage = async function (e) {
    const {
        image,
        options
    } = e.data;
    try {
      	// 使用支持webWorker的方法
        const result = await TinyPNG.compressWorkerImage(image, options);
        self.postMessage(result);
    } catch (error) {
        self.postMessage({ error: error.message });
    }
};
```



4. 在组件中使用

- 监听webworker的消息
- 使用 `TinyPNG.getImage` 处理文件信息
- 发送图片信息给webworker进行压缩
- 接收webworker返回的压缩结果

```js
<script>
// Import the worker
import ImageWorker from './imageWorker.worker.js'; // This is the bundled worker
import { getSizeTrans } from '../utils';
import TinyPNG from 'tinypng-lib';
export default {
  name: 'Base',
  data() {
    return {
      imgUrl: '',
      compressResult: {},
    }
  },
  mounted() {
    // Start the worker when the component is mounted
    this.worker = new ImageWorker();

    // Receive the message (compressed result) from the worker
    this.worker.onmessage = (e) => {
      this.compressing = false;
      const result = e.data;
      if (result.error) {
        console.error("Compression failed:", result.error);
      } else {
        const url = URL.createObjectURL(result.blob);
        this.imgUrl = url;
        this.compressResult = result;
      }
    };
  },
  methods: {
    async uploadImg(e) {
      const file = e.file;
      // 获取图片信息
      const image = await TinyPNG.getImage(file);
      this.compressing = true;
      // Send the file to the worker for compression
      this.worker.postMessage({
        image,
        options: {
          minimumQuality: 30,
          quality: 85
        }
      });
    }
  },
  beforeDestroy() {
    // Terminate the worker when the component is destroyed
    if (this.worker) {
      this.worker.terminate();
    }
  }
}
</script>
```



5. 说明：对于jpeg、jpg的图片不支持使用WebWorker压缩需要使用`TinyPNG.compressJpegImage` 进行压缩

```js
import TinyPNG from 'tinypng-lib';
TinyPNG.compressJpegImage(file, options)
```

## 总结

编译imagequant的过程比较坎坷，主要是rust的语言机制确实跟平常使用的语言不一样，需要学习的概念会多一些。不过获得的效果还是很不错的：

- 节省了服务器处理资源
- 节省了图片网络传输的时间
- 接入了WebWorker，可以并发执行任务且不阻塞
- 接入Service worker后可以做到离线使用

**小广告：**

- 开箱即用的图片压缩工具npm包：[tinypng-lib](https://www.npmjs.com/package/tinypng-lib)
- 图片压缩工具wasm包：[tinypng-lib-wasm](https://www.npmjs.com/package/tinypng-lib-wasm)
- 图片压缩工具体验地址：[https://tinypng.wcrane.cn/example](https://tinypng.wcrane.cn/example)