# 施工日志管理系统 · 前端

工程现场施工日志管理系统的 Flutter APP，支持项目/施工日志管理、现场照片上传加水印、PDF 导出、项目群聊、删除项目等功能。

## 技术栈

- Flutter（Dart 3+），目标平台：**Android APP**
- 网络请求：Dio + 全局 HttpOverrides（忽略自签名 SSL）
- 实时聊天：Socket.IO Client 2.x（**仅 WebSocket 传输**，Android 不支持 polling）
- 本地存储：shared_preferences（登录态 + 服务器地址自动记住）
- 图片处理：image_picker 1.0+（XFile 全平台）+ image（水印、压缩）
- 权限：INTERNET / ACCESS_NETWORK_STATE / CAMERA / READ_EXTERNAL_STORAGE / WRITE_EXTERNAL_STORAGE / ACCESS_FINE_LOCATION

## 目录结构

```
lib/
├── main.dart                # 入口 + AppColors + 全局主题 + HttpOverrides
├── models/                  # 数据模型（项目、施工日志）
├── screens/                 # 页面（登录、项目列表/详情、日志表单、聊天）
├── services/                # 服务（api、auth、socket、水印）
└── widgets/                 # 通用组件（图片选择器等）
```

## 快速开始

### 1. 安装依赖

```bash
flutter pub get
```

### 2. 本地运行

```bash
flutter run          # 连 USB 真机调试
flutter build apk --release   # 打包 release APK
```

默认后端地址为 `https://123.57.86.80:9304`（阿里云生产环境）。

## Socket.IO 连接要点

```
HTTP/HTTPS  →  Socket.IO 自动转换为 ws/wss
https://123.57.86.80:9304  →  wss://123.57.86.80:9304
```

**关键配置：**
- `socket_io_client.setTransports(['websocket'])` — Android 只支持 WebSocket
- `IO.OptionBuilder().enableForceNewConnection()` — 强制新连接避免复用导致的问题
- `extraHeaders: {'Authorization': 'Bearer <token>'}` — Socket.IO 用 token 鉴权
- Dart 全局 `HttpOverrides` 忽略自签名 SSL 证书

## AndroidManifest.xml 关键权限

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

## 踩坑记录

| 坑 | 根因 | 修复 |
|---|---|---|
| `connectionError` 登不上 | **AndroidManifest 缺 INTERNET 权限** | 加上 `<uses-permission android:name="android.permission.INTERNET"/>` |
| Socket.IO 连不上 | `socket_service` 用了 `https://` 不是 `wss://` | `https→wss, http→ws` |
| 照片 `XFile is not a subtype of File` | image_picker 1.0+ 全平台返回 XFile（不再是 File） | 统一 `XFile.readAsBytes()` + `MultipartFile.fromBytes()` |
| 自签名 SSL 连接失败 | Dart IO HttpClient 默认不信任自签名 | 全局 `HttpOverrides` + `network_security_config.xml` |
| socket_io_client 不发 polling | Android 上 `newInstance()` 硬编码只返回 WebSocket | 直接传 `['websocket']`，polling 在 Android 上无效 |
| Flutter Web 版已废弃 | 改为 Android APP 为主 | `usesCleartextTraffic=true` 允许 HTTP |

## 默认账号

- 用户名：`admin`
- 密码：`admin123`

## 对接后端

后端仓库：`construction-backend`，生产环境通过 Nginx + rust_frp 暴露。
