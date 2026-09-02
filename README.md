# 施工日志管理系统 · 前端

工程现场施工日志管理系统的 Flutter Web 前端，支持项目/施工日志管理、现场照片上传加水印、PDF 导出、项目群聊等功能。

## 技术栈

- Flutter（Dart 3+），目标平台：Web
- 网络请求：Dio
- 实时聊天：Socket.IO Client（polling 传输）
- 本地存储：shared_preferences（登录态 + 服务器地址）
- 图片处理：image_picker + image（水印、压缩）

## 目录结构

```
lib/
├── main.dart                # 入口 + 主题 + 路由
├── models/                  # 数据模型（项目、施工日志）
├── screens/                 # 页面（登录、项目列表/详情、日志表单、聊天）
├── services/                # 服务（api、auth、chat、socket、水印）
└── widgets/                 # 通用组件
```

## 快速开始

### 1. 安装依赖

```bash
flutter pub get
```

### 2. 本地运行（Web）

```bash
flutter run -d chrome
```

默认后端地址为 `http://localhost:5000`。

## 服务器地址配置

前后端分离部署，前端通过以下两种方式指定后端地址（二选一）：

### 方式一：登录页填写（推荐，运行时配置）

登录页顶部有「服务器地址」输入框，直接填写后端地址即可，例如：

```
http://192.168.1.100:5000
```

- 支持任意地址，无需重新编译
- 会自动保存，下次打开自动回填
- 地址格式校验，空值或非法 URL 会提示

### 方式二：构建时注入（编译期配置）

构建 Web 产物时通过 `--dart-define` 指定默认地址：

```bash
flutter build web --dart-define=API_BASE_URL=http://192.168.1.100:5000
```

> 注意：方式二的地址会被方式一（登录页填写）覆盖，且仅作为未填写时的默认值兜底。

## 构建与部署

```bash
# 构建 Web 产物（输出到 build/web）
flutter build web --release
```

将 `build/web` 目录部署到任意静态服务器（Nginx、Apache、对象存储等）即可。推荐在登录页填写服务器地址，避免每次换环境重新打包。

## 默认账号

- 用户名：`admin`
- 密码：`admin123`

> 账号由管理员在后台分配。

## 对接后端

后端仓库：`construction-backend`，默认监听 `0.0.0.0:5000`，已开启 CORS，前后端接口前缀统一为 `/api`。
