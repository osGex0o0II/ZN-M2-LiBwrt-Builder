# ZN-M2 LiBwrt 6.12 NSS Builds

**选择语言 / Select Language / 言語を選択**

[**中文**](#中文) | [**English**](#english) | [**日本語**](#日本語)

---

<a id="中文"></a>

## 中文

本仓库使用 GitHub Actions 自动编译适用于 **ZN-M2（兆能 M2）** 路由器的 LiBwrt 固件，基于 `openwrt-6.x` 的 `main-nss` 分支，启用 Qualcomm NSS 硬件加速。

### 硬件规格

| 版本 | 内存 | 闪存 | USB |
|------|------|------|-----|
| 1G-128M 改版 | 1GB | 128MB | 无 |
| 256M-128M 原厂 | 256MB | 128MB | 无 |

### 固件变体

**1G-128M HomeProxy**（`ZN-M2-1G-128M-6.12-NSS-HomeProxy`）
- 适用于 **1GB-128M** 改版 ZN-M2
- 集成 HomeProxy + sing-box 透明代理、ttyd 网页终端
- 配置文件：`configs/zn-m2-1g-128m-homeproxy.config`

**256M-128M Performance**（`ZN-M2-256M-128M-6.12-NSS-Performance`）
- 适用于 **256M-128M** 原厂 ZN-M2，纯有线路由
- 主路由功能：UPnP、Zerotier、WOL、定时重启、ttyd、流量统计
- 配置文件：`configs/zn-m2-256m-128m-performance.config`

### 共同特性

- Qualcomm NSS 硬件加速
- Aurora 主题、简体中文 LuCI、主机名 `ZN-M2`
- BBR 拥塞控制与基础网络调优
- 禁用 WiFi 和存储相关软件包（纯有线路由）

### 构建

打开 GitHub Actions，运行对应变体的 workflow，构建完成后从匹配的 release tag 下载固件。

### 默认登录

| 项目 | 值 |
|------|-----|
| 地址 | `192.168.1.1` |
| 用户 | `root` |
| 密码 | `password` |

[English](#english) · [日本語](#日本語)

---

<a id="english"></a>

## English

This repository builds wired-only LiBwrt `openwrt-6.x` `main-nss` firmware for **ZN-M2** using GitHub Actions, with Qualcomm NSS hardware acceleration enabled.

### Hardware Specs

| Variant | RAM | Flash | USB |
|---------|-----|-------|-----|
| 1G-128M upgraded | 1GB | 128MB | No |
| 256M-128M factory | 256MB | 128MB | No |

### Variants

**1G-128M HomeProxy** (`ZN-M2-1G-128M-6.12-NSS-HomeProxy`)
- For the **1GB-128M** upgraded ZN-M2
- Includes HomeProxy, sing-box transparent proxy, and ttyd web terminal
- Config file: `configs/zn-m2-1g-128m-homeproxy.config`

**256M-128M Performance** (`ZN-M2-256M-128M-6.12-NSS-Performance`)
- For the **256M-128M** factory ZN-M2, wired router
- Main router features: UPnP, Zerotier, WOL, scheduled reboot, ttyd, traffic statistics
- Config file: `configs/zn-m2-256m-128m-performance.config`

### Common Features

- Qualcomm NSS hardware acceleration
- Aurora theme, Simplified Chinese LuCI, hostname `ZN-M2`
- BBR congestion control and basic network tuning
- WiFi and storage-related packages disabled (wired-only router)

### Build

Open GitHub Actions, run the workflow for the variant you need, and download firmware from the matching release tag after the build completes.

### Default Login

| Item | Value |
|------|-------|
| Address | `192.168.1.1` |
| User | `root` |
| Password | `password` |

[中文](#中文) · [日本語](#日本語)

---

<a id="日本語"></a>

## 日本語

このリポジトリは GitHub Actions を使用して **ZN-M2** ルーター向けの LiBwrt ファームウェアを自動ビルドします。`openwrt-6.x` の `main-nss` ブランチをベースとし、Qualcomm NSS ハードウェアアクセラレーションを有効化しています。

### ハードウェア仕様

| バージョン | RAM | フラッシュ | USB |
|------------|-----|-----------|-----|
| 1G-128M 改造版 | 1GB | 128MB | なし |
| 256M-128M 純正 | 256MB | 128MB | なし |

### ファームウェアバリアント

**1G-128M HomeProxy**（`ZN-M2-1G-128M-6.12-NSS-HomeProxy`）
- **1GB-128M** 改造版 ZN-M2 向け
- HomeProxy + sing-box 透過プロキシ、ttyd Web ターミナルを統合
- 設定ファイル：`configs/zn-m2-1g-128m-homeproxy.config`

**256M-128M Performance**（`ZN-M2-256M-128M-6.12-NSS-Performance`）
- **256M-128M** 純正 ZN-M2 向け、有線ルーター
- 主な機能：UPnP、Zerotier、WOL、定期再起動、ttyd、トラフィック統計
- 設定ファイル：`configs/zn-m2-256m-128m-performance.config`

### 共通機能

- Qualcomm NSS ハードウェアアクセラレーション
- Aurora テーマ、簡体字中国語 LuCI、ホスト名 `ZN-M2`
- BBR 輻輳制御と基本ネットワークチューニング
- WiFi とストレージ関連パッケージを無効化（有線専用ルーター）

### ビルド

GitHub Actions を開き、必要なバリアントのワークフローを実行してください。ビルド完了後、対応するリリースタグからファームウェアをダウンロードできます。

### デフォルトログイン

| 項目 | 値 |
|------|-----|
| アドレス | `192.168.1.1` |
| ユーザー | `root` |
| パスワード | `password` |

[中文](#中文) · [English](#english)
