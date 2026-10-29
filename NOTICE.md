# 第三方组件与许可说明

本文件说明本仓库自身代码与固件镜像中第三方组件的许可关系。

## 本仓库

本仓库的构建脚本、配置文件和文档，除另有说明外，采用 **MIT 许可证**，完整文本见 [LICENSE](LICENSE)。

MIT 许可证仅适用于本仓库中由本项目贡献的内容，不改变、也不替代任何上游源码、软件包或固件组件的许可证。

## 固件镜像

固件镜像由 OpenWrt、ImmortalWrt、LiBwrt 源码以及大量第三方软件包编译而成。常见许可证包括：

- GPL-2.0、GPL-3.0
- LGPL-2.1、LGPL-3.0
- BSD 系列许可证
- MIT
- Apache-2.0
- 其他由上游项目指定的许可证

部分无线、网络加速或硬件相关组件可能包含厂商授权的二进制固件。这些组件继续适用其原始许可条款。

## 分发与源代码

- 分发固件时，必须同时遵守所有包含组件的许可证要求。
- GPL/LGPL 组件的源代码可从对应的上游仓库获取。
- 具体许可证和版权信息，请查看各上游仓库及软件包目录中的 `LICENSE`、`COPYING` 或软件包元数据。
- 本仓库不重新授权任何上游组件，也不替代上游项目的许可证声明。

主要上游项目：

- [OpenWrt](https://github.com/openwrt/openwrt)
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [LiBwrt](https://github.com/LiBwrt/LibWrt)
- [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt)
- [VIKINGYFY/packages](https://github.com/VIKINGYFY/packages)

## 无担保

固件和构建脚本按“现状”提供，不提供任何明示或暗示担保，包括但不限于适销性、特定用途适用性和不侵权担保。刷机、使用或分发本固件所产生的风险由使用者自行承担。

## 商标

OpenWrt、ImmortalWrt、LiBwrt、Qualcomm、兆能、集客等名称和标识归各自权利人所有。本项目与上述厂商或项目不存在隶属、赞助或背书关系。

## 说明

本文件用于说明许可关系，不构成法律意见。如对具体组件的许可证有疑问，请以对应上游项目的许可证文本为准。
