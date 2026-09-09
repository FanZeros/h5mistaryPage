# H5 构建产物（h5-dist 分支）

本分支仅包含 UrhoX/Maker 构建输出的 H5 产物，不含工程源码（scripts/assets 源目录在 master 分支）。

- 版本：1.0.6（build 5，2026-09-09 构建）
- 内容：index.html（引导器）、1.x.x.json、1.0.6/（清单）、assets/（哈希资源）、env.json、latest.json
- 引擎引导器与 WASM 运行时按 index.html 内置地址从官方 CDN 加载
- 部署：整个目录放到任意静态服务器根路径即可
- 注：构建时本机生成的 mac-token.json / user_info.json（运行时凭证）已剔除，不入库
