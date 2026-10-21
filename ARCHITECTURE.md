# 逆向分析报告 — 墨墨记忆卡 (com.maimemo.markji.android)

## APK 概况

- 包名：`com.maimemo.markji.android`
- 体积：50 MB，单 dex (`classes.dex` 48 MB)
- **加固**：梆梆安全 secneo(`com.secneo.apkwrapper.*`) —— dex 加密，
  jadx 只能解出壳层 (`AP/AW/H/CP` 等 7 个类)
- **Native 库**：
  - `libDexHelper.so` —— 梆梆加固的脱壳器
  - `libmmsqlcipher.so` —— SQLCipher 加密数据库
  - `libquickjs.so` —— **QuickJS 引擎**，运行 MMX JS 算法
  - `libmomoco.so`, `libwcdb.so`, `libsentry.so`, `libjutils.so` 等

## 关键发现 —— 算法不在 dex 里！

墨墨把调度算法**直接放在 `assets/` 下的两个明文 JS 文件**：

```
assets/
  mmx-5.js   # 8.6 KB — MMX-5 (12 params)
  mmx-6.js   # 7.1 KB — MMX-6 (21 params)
  mmdb/
    1611058178_1.db   # SQLCipher 加密的参数库（未破解）
  markji.db           # 加密的用户数据
```

通过 QuickJS 在 native 侧执行，避开 JVM 反编译，也便于热更新。

## 算法逆向结果

### 入口：`main(response_history, interval_history, sr_state, content_params, user_params)`

| 参数 | 含义 |
|---|---|
| `response_history` | 评分序列 `[1,1,2,4,...]`，编码 1..4 |
| `interval_history` | 相邻复习间隔天数 `[0,1,3,7,...]` |
| `sr_state`         | 上次输出的 `State` JSON（断点续传） |
| `content_params`   | 卡片级参数（当前 JS 中未使用，仅占位） |
| `user_params`      | 算法参数（12 或 21 维） |

### 返回 `{success, next_interval, sr_state}`

### MMX-5 关键代码（12 参数）

```js
init_state:  d = w[2] - (r-1)·w[3]
             s = 2^(w[0] + (r-1)·w[1])
next_d:      d' = d - (r-3)·w[4]         → clamp[1,10]
recall s':   s·(e^{w5}·d^{w6}·s^{w7}·(e^{w8(1-r)}-1)+1)
forget s':   w9·s^{w10}·e^{w11(1-r)}
curve:       R(t,s) = e^{ln(0.9)·t/s}
interval:    round(s·ln(0.85)/ln(0.9))
```

### MMX-6 关键代码（21 参数）

```js
init:        s = w[r-1]
             d = w[4] - e^{w[5](r-1)} + 1
next_d:      Δd = -w[6]·(r-3)
             d' = mean_reversion(init_d(1), d + Δd·(10-d)/9)
             mean_reversion: w[7]·init + (1-w[7])·current
curve:       factor = 0.9^{1/decay} - 1,  decay = -w[20]
             R = (1 + factor·t/s)^decay
recall s':   s·(1 + e^{w8}·(11-d)·s^{-w9}·(e^{(1-r)w10}-1)·[w16 if r=4])
forget s':   w11·d^{-w12}·((s+1)^{w13}-1)·e^{(1-r)w14}·[w15 if r=1]
```

### 评分映射（与 APK `ratings` 表一致）

```
认识(1)→3   模糊(2)→2   忘记(3)→1   熟知(4)→4
```

## 加密数据库 `mmdb`

`mmdb/1611058178_1.db` 头部为随机字节 —— SQLCipher 加密，密钥应在
`libmmsqlcipher.so` 或加固解密后的 dex 中。含真实 `user_params`，
本实现用 FSRS-6 公开默认参数替代（同构公式）。

## 与 FSRS 的关系

- **MMX-5 ≈ FSRS-4.5**（同形 19 参数子集）
- **MMX-6 ≈ FSRS-6**（完整 21 参数，含 `decay`）
- 学术同源：都基于 DHP 模型（Ye et al., KDD'22）
- FSRS 作者任职墨墨；MMX 为其产品内部版本，FSRS 为开源版

## 脱壳路线（未完成，供参考）

1. 模拟器+root 装 APK，运行后用 `frida-dump` / `BlackDex` 抓内存中解密 dex
2. 静态分析 `libDexHelper.so` 找到解密例程
3. 直接提取 native 层 `user_params`（可能在 `libmomoco.so`）

## 参考

- [memodocs.maimemo.com — MMX](https://memodocs.maimemo.com/docs/MMX)
- [KDD'22 DHP+SSP-MMC](https://memodocs.maimemo.com/docs/2022_KDD/)
- [TKDE'23 SSP-MMC-Plus](https://memodocs.maimemo.com/docs/2023_TKDE/)
- [MMX vs Anki FSRS](https://memodocs.maimemo.com/docs/markji-mmx-vs-anki-fsrs/)
- [算法演进史](https://memodocs.maimemo.com/docs/maimemo-algorithm-updates/)
