# AccountSwitch

AccountSwitch 是一个 macOS 工具，方便在工作、个人或不同地区的 Apple 账户之间切换 App Store 登录。可以在一个窗口管理账号，也可以在设置中开启菜单栏入口。

- 为账号记录别名、登录邮箱或手机号、商店地区和头像，支持复制登录标识。
- 按账号选择是否把密码保存在本机钥匙串。获得辅助功能权限后，可从账号列表发起切换，并在识别到的 App Store 登录表单中填写凭据。
- 默认在切换或移除账号时要求验证 Mac 用户身份。App Store 已登录时，退出原账号需要确认，双重认证仍在 App Store 内完成。

## 下载

[下载 v0.6（Apple 芯片 Mac）](https://github.com/LoveMu-498/AccountSwitch/releases/tag/v0.6)。需要 macOS 14 或更新版本。解压后将 `AccountSwitch.app` 拖到「应用程序」。

安装包使用 ad-hoc 签名，未经 Apple 公证。若 macOS 阻止打开，可使用下面的步骤从源码构建。

## 使用

1. 点「添加账号」，填写别名和登录邮箱或手机号。地区和头像可按需设置。
2. 使用「打开 App Store」手动登录，或在账号菜单中选择「管理密码」，保存密码后按提示授权辅助功能。
3. 点该账号的「切换」。若 App Store 要求双重认证，或自动填写遇到无法识别的界面，请在 App Store 内继续。账号地区用于标记档案，实际商店地区由登录的 Apple 账户决定。

## 隐私

账号档案和头像保存在本机，密码单独保存于本机登录钥匙串。手动复制时，登录邮箱或手机号进入系统剪贴板。自动填写仅在用户发起切换后向识别到的 App Store 登录表单填入凭据。地区选择器会从 Apple 的公开支持页面刷新地区清单，离线时使用自带清单。应用无需 API 密钥。

## 从源码构建

安装包含 Swift 6 的 Xcode 或命令行工具，在仓库根目录运行：

```sh
swift test
./script/build_and_run.sh
```

构建脚本将 App 放在 `dist/AccountSwitch.app` 并打开。运行 `./script/build_and_run.sh --package` 可生成当前 Mac 架构的 Release 构建，输出到 `dist/release/AccountSwitch.app`。

## 许可与致谢

AccountSwitch 使用 [Apache License 2.0](LICENSE)。

账号列表与切换流程的设计参考了 Licardo 和 Bigwig Club 贡献者的 [Account-Switcher v1.2.0](https://github.com/Bigwig-Club/Account-Switcher/tree/v1.2.0)。原项目用于快速切换多个 Mac App Store 账号，减少手动退出与重新登录的步骤，账号数据保存在本机。该版本的许可为 [Apache License 2.0](https://github.com/Bigwig-Club/Account-Switcher/blob/v1.2.0/LICENSE)。感谢原项目作者与贡献者。

App Store 地区清单参考 [Apple 的媒体服务可用性页面](https://support.apple.com/en-us/118205)。
