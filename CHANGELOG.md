# 更新日志

## v1.0.0 — 首个开源版本

### 📋 施工日志
- 施工日志新建 / 编辑：天气气温、出勤人数、机械台班、施工内容、质量安全情况
- 现场照片拍照 / 相册多选，自动叠加水印（项目名、日期时间、GPS 地址与经纬度）
- 日志按项目分组、按日期归档

### 💬 项目群聊
- 文字 / 图片 / 文件 / GPS 点位消息，Socket.IO + WebSocket 实时推送
- 消息**永久保存在服务器**，换机重装历史完整同步
- 已读回执、消息撤回、聊天记录关键词搜索
- GPS 点位一键拉起高德地图查看 / 导航
- 长按进入**多选模式**，勾选消息转发 / 分享到微信、QQ（文字+点位自动生成导航链接，图片文件原样发送）

### 🔒 连接与安全
- 登录页可自定义服务器地址并记忆，一套 App 连接任意自建后端
- 支持自签名 HTTPS 证书与内网 HTTP
- 弱网断线自动重连，上传状态可见

### 📦 获取
- Android APK：见 [Releases](https://github.com/qianqianjie-999/construction-frontend/releases)
- 自行编译：`flutter build apk --release --dart-define=API_BASE_URL=https://你的服务器:9304`
- 后端部署：见 [construction-backend](https://github.com/qianqianjie-999/construction-backend) 的 `docs/DEPLOY.md`
