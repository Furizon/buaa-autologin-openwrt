# BUAA AutoLogin · OpenWrt Shell

面向低配置 OpenWrt 路由器的北航校园网 SRun 自动登录客户端。使用系统自带的 `/bin/sh`（BusyBox ash），路由器不需要安装 Python、Bash 或编译器，也不需要交叉编译。

已在 **Xiaomi Mi Router AC2100 / MediaTek MT7621 / OpenWrt 22.03.0 / Linux 5.10.138** 上由使用者确认登录及联网正常。这是小米 AC2100，不是 Redmi AC2100。其他设备及固件请先运行自检；这条实机记录不是对旧固件的推荐，也不代表所有 OpenWrt 版本都经过测试。

## 功能与边界

- 查询门户状态，离线时获取新 challenge 并登录；在线时不重复认证。
- 默认每 60 秒检查一次，连续登录未确认成功时退避，最多尝试 5 次后退出。
- HTTPS 校验证书，不跟随接口重定向；认证 URL 不放到进程参数中。
- 支持前台运行和 OpenWrt procd 开机服务。
- 不修改 TTL、HTTP User-Agent 转发规则、MAC、DNS、防火墙或代理配置，不依赖 xmurp-ua、ShellCrash。
- 仅处理已有账号的常规认证；验证码、账号限制等需要通过学校门户处理。

## 依赖

适用于使用 `opkg` 的 OpenWrt。先在路由器中安装依赖：

```sh
opkg update
opkg install curl openssl-util jsonfilter ca-bundle
```

还需要 BusyBox 的 `od`、`awk`、`tr`、`sed`、`mktemp`、`date` 等命令，以及支持 64 位整数运算的 shell。实际新增空间取决于固件已有的库，不能用脚本大小估算总安装占用。

认证前无法下载软件包时，先通过其他可用网络联网，或准备与当前固件匹配的离线 IPK 及依赖。不要混用其他固件版本的软件源。

## 快速开始

### 1. 上传文件

下载 Release 中的运行包并解压；只需要上传 `campus-login.sh` 和 `buaa-campus-login.init`。仓库源码中的对应文件位于 `openwrt_sh/`。

先在路由器创建目录：

```sh
mkdir -p /usr/buaa-login
```

通过 SFTP/SCP 或其他文件传输工具，把两个文件上传到 `/usr/buaa-login/`。较旧 OpenWrt 不提供 SFTP 服务时，现代 OpenSSH 的 `scp` 可使用 `-O` 切换到传统 SCP；该选项在电脑端使用。

脚本必须使用 LF 换行。不要通过编辑器把 `.sh` 或 `.init` 保存为 CRLF。

### 2. 自检、配置和登录

```sh
sh /usr/buaa-login/campus-login.sh --check
sh /usr/buaa-login/campus-login.sh --setup
sh /usr/buaa-login/campus-login.sh --once
sh /usr/buaa-login/campus-login.sh --status
```

`--check` 验证依赖、64 位运算、摘要算法和固定 SRun 编码向量，不访问认证服务器。`--setup` 交互输入账号与密码，密码输入不回显。**账号大小写必须与学校账号一致。** 发布包不包含真实账号或密码。

配置保存在 `/etc/buaa-campus-login.conf`，权限为 `600`，密码是本地明文。不要上传此文件。再次执行 `--setup` 会重建配置，并重置服务器、接入点等设置。

### 3. 开机启动

确认 `--status` 显示 `online`，且实际联网正常后执行：

```sh
cp /usr/buaa-login/buaa-campus-login.init /etc/init.d/buaa-campus-login
chmod 755 /etc/init.d/buaa-campus-login
/etc/init.d/buaa-campus-login enable
/etc/init.d/buaa-campus-login start
```

本发布包的 init 文件使用 `/usr/buaa-login/campus-login.sh`。如果采用其他安装位置，必须同步修改 init 文件内的路径。旧安装放在 `/root/buaa-login/` 时尤其需要核对，避免启动旧副本。

```sh
# 查看日志
logread | grep -E 'campus-login|Portal status|Login |Stopped after'

# 修改配置后重启服务
/etc/init.d/buaa-campus-login restart

# 停止服务并取消开机启动
/etc/init.d/buaa-campus-login stop
/etc/init.d/buaa-campus-login disable
```

服务不设置自动 respawn，避免退出后绕过 5 次失败的限制。服务日志由 procd 收集，不单独持续写入闪存。排查并解决问题后，可以手动再次启动服务。

## 命令与配置

| 参数 | 用途 |
| --- | --- |
| `--check` | 离线检查依赖与协议编码 |
| `--setup` | 交互生成配置 |
| `--once` | 检查状态，必要时尝试一次登录 |
| `--status` | 只查询状态，确认在线时退出码为 0 |
| `--watch` | 前台持续检查，Ctrl+C 停止 |
| `--config /path/to/file` | 指定配置文件 |

不带参数默认运行 `--once`。手动运行 `--once` 或另一个 `--watch` 前先停止后台服务；`--status` 可以独立查询。

配置采用字面量 `key=value`，**不加额外引号，不使用 Markdown 链接，也不要 `source` 配置文件**：

```ini
username=YOUR_USERNAME
password=YOUR_PASSWORD
server=https://gw.buaa.edu.cn
ac_id=67
interval=60
interface=
ca_file=
```

- `server`：实际 HTTPS 认证门户。不要写成 `[https://…](https://…)`。
- `ac_id`：默认 67；不同接入网络可能不同，以实际网页登录入口为准。
- `interval`：常规检查间隔，单位为秒，允许 30～3600。
- `interface`：可选的实际 Linux 网络设备名，默认留空；OpenWrt 逻辑接口名称不一定是设备名。
- `ca_file`：可选的可信 CA PEM 文件路径。

账号和密码各最多 256 个 UTF-8 字节；空格、引号、反斜杠、`$`、`&`、`=` 按字面处理，不执行。不支持换行和 NUL；允许配置文件使用 CRLF。客户端 IP 每次取门户识别到的 IPv4，不写死地址。

程序忽略环境代理，但系统级透明代理/TUN 仍可能影响网络路径。HTTPS 失败时检查时间与可信 CA，不使用 `-k` 绕过证书验证。

## 状态判定与失败重试

登录响应中的 `error` 和 `res` 同时为 `ok`，才报告 `Portal accepted login.`；随后立即再次查询状态。只有确认在线，才清零连续失败次数。门户在线状态不等于所有外网站点都可达。

- `--watch` 仅在明确离线时登录；状态未知或网络请求失败时等待，不反复提交凭据。
- `--once` 在成功获得但无法识别的状态响应后也可尝试一次；状态请求本身失败则退出。
- 默认连续未确认登录时依次等待 120、240、480、900 秒，第 5 次失败退出。自定义间隔时按 `interval × 2^失败次数` 计算，上限 900 秒。获取 challenge 失败也计入登录失败次数。
- 单实例锁为 `/tmp/buaa-campus-login.lock`。正常退出和重启会清理；强制杀进程可能留下锁。先停服务，使用 `ps w | grep '[c]ampus-login'` 确认没有运行实例，才可用 `rmdir /tmp/buaa-campus-login.lock` 清理空锁目录。

## 常见问题

### `curl=6`：无法解析认证域名

```sh
nslookup gw.buaa.edu.cn
cat /tmp/resolv.conf.d/resolv.conf.auto
logread | grep -i rebind | tail -n 20
```

确认 DNS 上游和认证域名正确。如果日志明确显示可信校园域名被 DNS rebind 防护拦截，可只为需要的域名添加例外。下面只放行认证域名，保留全局防护：

```sh
uci add_list dhcp.@dnsmasq[0].rebind_domain='/gw.buaa.edu.cn/'
uci commit dhcp
/etc/init.d/dnsmasq restart
```

不要重复添加已有条目，也不要仅因一个域名出错就关闭全局 rebind 防护。`buaa.edu.cn`、`www.buaa.edu.cn` 与 `gw.buaa.edu.cn` 是不同查询目标；没有 A 记录、只有 AAAA 记录时，也应区分 IPv4 DNS 与 IPv6 连通性问题。

### `Login rejected (ecode=...)`

先在学校网页登录并查看具体提示。曾有实机 `E2531` 由账号大小写错误引起，但不要把所有认证失败都归结为密码问题。`ecode=0` 本身也不保证成功，因为脚本还检查 `error` 和 `res`。

如需查看有限的错误字段，可在停止后台服务后生成诊断副本：

```sh
sed '/code=$(field ecode)/a\
    for key in error res ecode error_msg suc_msg; do log "$key=$(field "$key")"; done
' /usr/buaa-login/campus-login.sh > /tmp/buaa-login-debug.sh
sh /tmp/buaa-login-debug.sh --once
```

输出可能包含服务端返回的账号信息，分享前打码。不要使用 `sh -x`，也不要公开密码、challenge、完整认证 URL 或认证参数。临时副本不要加入自启动。

### `challenge_expire_error`

门户认为本次 challenge 已过期或失效。先停止高负载测试，排除其他自动登录客户端或网页登录的并发影响，再使用新 challenge 进行一次登录。可能与处理延迟、网络或门户会话有关，不能仅凭此错误归因于 TTL 检测。

一次实机记录中，获取 challenge 到准备提交耗时约 0.52 秒，登录请求往返约 0.64 秒，并被门户接受。这只是单次记录，不是性能保证，也未确定先前 challenge 失效的根因。

### `Login accepted but online status is not confirmed.`

认证请求被接受，但紧接着的查询尚未确认在线。等待 5～10 秒，再运行：

```sh
sh /usr/buaa-login/campus-login.sh --status
```

同时从终端设备验证实际联网。仍离线时查看门户提示；实际联网正常但状态持续未知时，需要检查状态接口格式。不要把 `ecode=0` 或“请求被接受”直接等同于已在线。

### 路由器掉线或重启

先用 `uptime` 区分整机重启和单纯认证/代理掉线。CPU 占用高、一次 ping 超时或 `ttl=61` 都不能单独证明重启原因。另行排查内核模块、代理负载、内存、驱动和供电；本客户端不需要安装 xmurp-ua。

OpenWrt 日志通常保存在内存，重启后会丢失。可在电脑端持续保存 `ssh root@路由器地址 "logread -f"` 的输出。现有实机记录确认登录可用，整机长期稳定性及重启根因尚未验证，不应把其他模块的稳定性归功或归咎于本脚本。

## 开发与验证

仓库结构：

```text
README.md
openwrt_sh/
  campus-login.sh
  buaa-campus-login.init
  tests/
tests/
  protocol_reference.py
```

开发机需要 Python 3.9+ 和 POSIX shell，以及 OpenSSL 和常用 Unix 命令。**Python 仅用于开发测试，路由器运行不需要。** 从仓库根目录执行：

```sh
python3 openwrt_sh/tests/test_shell.py --shell /bin/dash
python3 openwrt_sh/tests/test_flow.py --shell /bin/dash
python3 openwrt_sh/tests/test_watch.py --shell /bin/dash
```

Windows 可将 `--shell` 指向 Git for Windows 的 `usr/bin/dash.exe`。测试包括 19 组协议向量、12 项模拟流程、自检以及 2 项持续模式策略测试。协议参考实现只用于测试，不包含可运行的个人账号客户端。

模拟 curl/jsonfilter 的测试不验证真实 TLS 或 OpenWrt jsonfilter；开发机 dash 测试不等同于所有 BusyBox ash 版本测试。已有人在上述 Mi AC2100 上确认真实认证与联网正常，其他硬件、长期资源占用和学校后续接口变化仍需实际验证。

## 反馈问题

请提供：设备型号、`ubus call system board` 的固件信息、脚本命令及脱敏日志、网页能否登录、`--status` 的输出，以及是否使用透明代理。不要提交真实配置文件或认证抓包。

参考：[OpenWrt shell 编程](https://openwrt.org/docs/guide-developer/write-shell-script)、[OpenWrt 日志](https://openwrt.org/docs/guide-user/base-system/log.essentials)、[OpenWrt DNS/DHCP 配置](https://openwrt.org/docs/guide-user/base-system/dhcp)。
