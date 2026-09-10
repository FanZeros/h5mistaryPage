# 迷境探索 — H5 公开页面

UrhoX 构建产物（H5），通过 GitHub Pages 公开访问。

- 引擎运行时按 index.html 内置地址从官方 CDN 加载（需联网）
- coi-serviceworker 注入 COOP/COEP，提供 SharedArrayBuffer 所需的跨域隔离
- 本地调试：`npx serve -l 8080 .`（serve.json 已含所需响应头）

线上地址：https://fanzeros.github.io/h5mistaryPage/
