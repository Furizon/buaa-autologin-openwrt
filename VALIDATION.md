# v1.0.0 验证记录

验证日期：2026-09-24。

## 开发机验证

环境：Windows，Python 3.10，Git for Windows 提供的 dash。

- `test_shell.py`：Shell 语法与 19 组协议向量通过。
- `test_flow.py`：`--check` 自检、12 项模拟传输/JSON/登录流程通过。
- `test_watch.py`：未知状态不登录、未确认在线时失败累计与退避退出，两项通过。
- 运行 ZIP 结构与 CRC 检查通过；只有 README、Shell 脚本、init 服务三个文件，使用 UTF-8/LF。
- 发布目录采用逐文件白名单整理；未包含旧电脑版、个人配置、日志、抓包或旧压缩包。

## 实机反馈

使用者确认在北京航空航天大学学院路校区，Xiaomi Mi Router AC2100 / OpenWrt 22.03.0 / Linux 5.10.138 上登录和联网正常。

曾观察到 challenge 失效，以及门户接受登录后紧接着状态尚未确认的情况，之后认证恢复。没有据此修改成功判定或关闭 HTTPS 校验。此反馈不是所有固件兼容性、性能上限或长期稳定性的验证；路由器此前重启的根因尚未确定。

本次发布保留已验证的运行脚本，init 路径统一为 `/usr/buaa-login/campus-login.sh`。模拟测试不能代替真实 TLS、设备 jsonfilter 与 BusyBox ash 的跨版本测试。

## v1.0.1 文档补充

明确学院路校区已验证、沙河校区未验证。运行脚本及 init 文件与 v1.0.0 相同，本次仅更新文档和打包信息。
