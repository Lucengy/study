# CentOS 7 安装 GCC 14.3.0 指导手册

## 1. 本手册解决什么问题

Ratis 当前使用的 `protoc-gen-grpc-java 1.77.1` 是 Linux 原生程序。CentOS 7 自带的
`/lib64/libstdc++.so.6` 较旧，运行它时可能出现：

```text
CXXABI_1.3.8 not found
CXXABI_1.3.9 not found
GLIBCXX_3.4.21 not found
```

本手册把 GCC 14.3.0 安装到：

```text
/usr/local/gcc-14.3.0
```

安装完成后：

```text
/usr/bin/gcc                       仍然是 CentOS 系统 GCC
/lib64/libstdc++.so.6              不修改
/usr/local/gcc-14.3.0/bin/gcc            新 GCC
/usr/local/gcc-14.3.0/lib64/libstdc++.so.6 新 C++ 运行库
```

这是刻意设计的隔离方式。不要覆盖系统 GCC，不要修改 `/lib64/libstdc++.so.6` 的软链接。

CentOS 7 的系统 GCC 4.8.5 在直接引导 GCC 14.3.0 时，可能在 GCC 自带的 gettext 中报
`scratch_buffer.gl.h: unknown type name 'max_align_t'`。因此本手册采用两阶段工具链：

```text
系统 GCC 4.8.5
  -> GCC Toolset 11（只作为引导编译器）
  -> /usr/local/gcc-14.3.0（最终工具链）
```

不要通过修改 `scratch_buffer.gl.h` 或手工定义 `max_align_t` 绕过问题；这会把工具链构建变成
未经验证的源码补丁实验。

## 2. 时间和资源预期

源码编译 GCC 比安装普通 RPM 慢很多。具体时间取决于虚拟机 CPU 和磁盘性能，建议至少准备：

```text
CPU：2 核以上，推荐 4 核
内存：4 GB 以上，推荐 8 GB
空闲磁盘：至少 15 GB，推荐 25 GB
时间：可能需要 1～4 小时
```

三台虚拟机先只在 node1 完整操作。node1 验证成功后，再处理 node2、node3。

开始前建议为虚拟机创建快照。快照是回退手段，不是跳过命令验证的理由。

## 3. 路径规划

本手册统一使用：

```text
源码与下载：/home/ratis/toolchains/src
构建目录：  /home/ratis/toolchains/build/gcc-14.3.0
安装目录：  /usr/local/gcc-14.3.0
构建日志：  /home/ratis/toolchains/logs/gcc-14.3.0-build.log
```

如果你以 `root` 登录，仍然可以使用这些路径。不要把 GCC 源码或构建目录放进 Ratis Git 项目。

## 4. 阶段一：安装基础构建工具

### 4.1 查看系统信息

```bash
cat /etc/centos-release
uname -m
df -h /home /usr/local
free -h
nproc
```

期望架构是：

```text
x86_64
```

### 4.2 安装依赖

```bash
yum groupinstall -y "Development Tools"
yum install -y wget curl tar xz gzip bzip2 perl texinfo
yum install -y centos-release-scl
yum install -y devtoolset-11-gcc devtoolset-11-gcc-c++
```

CentOS 7 已进入归档阶段。如果 `yum` 报仓库不可用，应使用你所在环境可访问的 Vault 或内部镜像，
不要为了继续实验而下载来源不明的 RPM。

### 4.3 查看系统编译器

```bash
gcc --version
g++ --version
make --version
```

这里通常会看到 GCC 4.8.5。它是 CentOS 7 的系统编译器，但本手册不再让它直接引导
GCC 14.3.0，因为当前环境会在 bundled gettext 中遇到 `max_align_t` 错误。

### 4.4 启用 GCC Toolset 11 引导编译器

```bash
source /opt/rh/devtoolset-11/enable
```

检查：

```bash
which gcc
which g++
gcc --version
g++ --version
```

应显示 `/opt/rh/devtoolset-11` 下的命令和 GCC 11。它只负责构建最终的 GCC 14.3.0，
不会成为本手册最终安装路径。

如果 `/opt/rh/devtoolset-11/enable` 不存在，说明 GCC Toolset 11 没有成功安装，不能继续配置
GCC 14.3.0。本手册只构建 C/C++ 前端，不构建 Ada、D、Go、Rust 等前端。

## 5. 阶段二：下载并校验 GCC 14.3.0

### 5.1 创建目录

```bash
mkdir -p /home/ratis/toolchains/src
mkdir -p /home/ratis/toolchains/build
mkdir -p /home/ratis/toolchains/logs
cd /home/ratis/toolchains/src
```

### 5.2 从 GNU 官方站点下载

```bash
curl -fLO https://gcc.gnu.org/pub/gcc/releases/gcc-14.3.0/gcc-14.3.0.tar.xz
curl -fLO https://gcc.gnu.org/pub/gcc/releases/gcc-14.3.0/sha512.sum
```

如果机器必须使用代理，先确认当前终端中的 `http_proxy`、`https_proxy` 与 `no_proxy` 设置正确。

### 5.3 校验 SHA-512

```bash
grep 'gcc-14.3.0.tar.xz$' sha512.sum | sha512sum -c -
```

必须得到：

```text
gcc-14.3.0.tar.xz: OK
```

GNU 官方公布的 `gcc-14.3.0.tar.xz` SHA-512 是：

```text
cb4e3259640721bbd275c723fe4df53d12f9b1673afb3db274c22c6aa457865d
ccf2d6ea20b4fd4c591f6152e6d4b87516c402015900f06ce9d43af66d3b7a93
```

上面为了排版分为两行；实际哈希是连续的 128 个十六进制字符。日常验证以官方
`sha512.sum` 和 `sha512sum -c` 的结果为准。校验失败时停止，不要解压或编译。

### 5.4 解压

```bash
tar -xf gcc-14.3.0.tar.xz
test -x gcc-14.3.0/configure
echo $?
```

最后一个命令应输出 `0`。

## 6. 阶段三：下载 GCC 配套数学库

进入源码目录：

```bash
cd /home/ratis/toolchains/src/gcc-14.3.0
```

运行 GCC 自带脚本：

```bash
./contrib/download_prerequisites
```

它会下载 GCC 构建需要的 GMP、MPFR、MPC、isl，并在源码树中建立对应链接。

检查：

```bash
ls -ld gmp mpfr mpc isl
```

四个名称都应该存在。如果脚本下载失败，不要直接执行下一步；先处理 DNS、代理或下载源问题。

## 7. 阶段四：在独立目录配置构建

GNU 官方建议源码目录和构建目录分开。不要在 `gcc-14.3.0` 源码目录中直接运行 `configure`。

```bash
mkdir -p /home/ratis/toolchains/build/gcc-14.3.0
cd /home/ratis/toolchains/build/gcc-14.3.0
```

确认当前目录基本为空：

```bash
pwd
ls -la
```

执行配置：

```bash
source /opt/rh/devtoolset-11/enable
which gcc
gcc --version

export CONFIG_SHELL=/bin/bash
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS LIBRARY_PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH

mkdir -p /usr/local/gcc-14.3.0

CC="$(command -v gcc)" CXX="$(command -v g++)" \
/home/ratis/toolchains/src/gcc-14.3.0/configure \
  --prefix=/usr/local/gcc-14.3.0 \
  --enable-languages=c,c++ \
  --disable-multilib \
  --disable-nls \
  --enable-bootstrap
```

参数含义：

```text
--prefix=/usr/local/gcc-14.3.0  安装到独立目录，不覆盖系统 GCC
--enable-languages=c,c++  只构建本实验需要的 C 和 C++
--disable-multilib        只构建 64 位，避免 CentOS 7 缺少 32 位开发头文件
--disable-nls             不构建本地化消息，减少依赖
--enable-bootstrap        执行原生三阶段 bootstrap，并比较阶段产物
```

配置输出中使用的引导编译器必须来自 GCC Toolset 11。`mkdir -p` 提前建立 prefix，也避免
部分子项目在规范化绝对路径时报告 `/usr/local/gcc-14.3.0: No such file or directory`。

成功标志是命令退出码为 `0`，并且当前目录生成顶层 `Makefile`：

```bash
echo $?
test -f Makefile
echo $?
```

两个结果都应为 `0`。

## 8. 阶段五：编译 GCC

仍在构建目录中执行：

```bash
cd /home/ratis/toolchains/build/gcc-14.3.0
set -o pipefail
make -j"$(nproc)" 2>&1 | tee /home/ratis/toolchains/logs/gcc-14.3.0-build.log
build_status=${PIPESTATUS[0]}
echo "GCC build exit code: ${build_status}"
test "${build_status}" -eq 0
```

为什么不能只看 `tee`：管道末端是 `tee`。不启用 `pipefail` 或不检查 `PIPESTATUS[0]` 时，
前面的 `make` 失败仍有可能被误判成命令成功。

### 8.1 内存不足时

如果日志中出现：

```text
Killed
cc1plus: out of memory
internal compiler error 后紧接 Killed
```

先检查：

```bash
free -h
dmesg | tail -n 50
```

然后降低并行度重新执行：

```bash
make -j2
```

内存仍不足时使用 `make -j1`。不要反复使用过高的 `-j`。

### 8.2 磁盘不足时

```bash
df -h /home /usr/local
du -sh /home/ratis/toolchains/build/gcc-14.3.0
```

不要在磁盘耗尽后直接继续构建；先扩容或清理确认无用的数据。

## 9. 阶段六：安装到 /usr/local

只有上一阶段退出码为 `0` 才执行：

```bash
cd /home/ratis/toolchains/build/gcc-14.3.0
make install
```

非 root 用户使用：

```bash
sudo make install
```

检查安装文件：

```bash
test -x /usr/local/gcc-14.3.0/bin/gcc
test -x /usr/local/gcc-14.3.0/bin/g++
find /usr/local/gcc-14.3.0 -name 'libstdc++.so.6*' -ls
```

## 10. 阶段七：只为当前用户启用 GCC 14.3.0

创建独立环境文件：

```bash
vi "$HOME/.gcc-14.3.0-env"
```

写入：

```bash
export GCC_HOME=/usr/local/gcc-14.3.0
export PATH="$GCC_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$GCC_HOME/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CC="$GCC_HOME/bin/gcc"
export CXX="$GCC_HOME/bin/g++"
```

保存后，在当前终端启用：

```bash
source "$HOME/.gcc-14.3.0-env"
```

验证：

```bash
which gcc
which g++
gcc --version
g++ --version
echo "$LD_LIBRARY_PATH"
```

期望：

```text
/usr/local/gcc-14.3.0/bin/gcc
/usr/local/gcc-14.3.0/bin/g++
gcc (GCC) 14.3.0
g++ (GCC) 14.3.0
```

确认新 `libstdc++` 包含 Ratis 插件需要的符号：

```bash
new_libstdcpp="$(g++ -print-file-name=libstdc++.so.6)"
echo "$new_libstdcpp"
strings "$new_libstdcpp" | grep -E 'GLIBCXX_3.4.21|CXXABI_1.3.8|CXXABI_1.3.9'
```

三个符号都应出现。

### 10.1 验证成功后再设置自动加载

确认手动 `source` 没有问题后，再执行：

```bash
grep -qF '. "$HOME/.gcc-14.3.0-env"' "$HOME/.bashrc" \
  || echo '. "$HOME/.gcc-14.3.0-env"' >> "$HOME/.bashrc"
```

重新登录 SSH 后再次检查：

```bash
which gcc
gcc --version
```

不要把 `LD_LIBRARY_PATH` 直接写入 `/etc/profile`。本实验先控制在当前用户范围内，减少对系统服务的影响。

## 11. 阶段八：验证 protoc-gen-grpc-java

进入 Ratis 项目：

```bash
cd /home/ratis/src/ratis
source "$HOME/.gcc-14.3.0-env"
```

如果上一次构建已经下载出插件，检查动态库解析：

```bash
plugin='ratis-proto/target/protoc-plugins/protoc-gen-grpc-java-1.77.1-linux-x86_64.exe'
test -x "$plugin"
ldd "$plugin" | grep libstdc++
```

期望 `libstdc++.so.6` 指向：

```text
/usr/local/gcc-14.3.0/lib64/libstdc++.so.6
```

如果仍然指向 `/lib64/libstdc++.so.6`，先检查：

```bash
echo "$LD_LIBRARY_PATH"
ls -l /usr/local/gcc-14.3.0/lib64/libstdc++.so.6
```

不要修改 `/lib64` 下的文件。

## 12. 阶段九：重新构建 Ratis

必须在已经 `source` 新环境的同一个终端执行：

```bash
cd /home/ratis/src/ratis
source "$HOME/.gcc-14.3.0-env"

./mvnw -pl ratis-examples -am \
  -DskipTests \
  -Dcheckstyle.skip \
  -Drat.skip \
  package
```

成功后检查：

```bash
ls -lh ratis-examples/target/ratis-examples-*.jar
```

这次 `package` 成功说明：

```text
protoc-gen-grpc-java 已经能加载新版 libstdc++
项目完成了本次跳过测试的 package
```

但它不说明测试已经通过，因为命令明确使用了 `-DskipTests`。

## 13. 三台节点的执行策略

### 策略 A：三台分别编译

优点：每台工具链都由本机生成，最容易解释和排查。

缺点：耗时长，三台总共需要执行三次完整 bootstrap。

学习阶段建议先完成 node1，然后在 node2、node3 重复相同步骤并分别记录：

```text
gcc --version
g++ -print-file-name=libstdc++.so.6
ldd protoc-gen-grpc-java... | grep libstdc++
Ratis package 最终结果
```

### 策略 B：在相同系统的虚拟机间复制已安装目录

只有三台机器都是相同的 CentOS 7.x、相同的 `x86_64` 架构，并且安装路径都保持
`/usr/local/gcc-14.3.0` 时，才考虑从 node1 打包安装目录后分发。第一次学习建议优先使用策略 A，
避免把系统差异隐藏起来。

## 14. 常见问题

### 14.1 `scratch_buffer.gl.h: unknown type name 'max_align_t'`

这表示实际使用的引导编译器仍是 CentOS 7 的 GCC 4.8.5，或当前 build 目录残留了使用
GCC 4.8.5 生成的配置。

不要在旧 build 目录直接切换编译器继续 `make`。保留失败现场并建立全新目录：

```bash
cd /home/ratis/toolchains/build
failed_dir="gcc-14.3.0.failed-gcc48-$(date +%Y%m%d-%H%M%S)"
mv gcc-14.3.0 "$failed_dir"
mkdir gcc-14.3.0
cd gcc-14.3.0
```

然后重新执行：

```bash
source /opt/rh/devtoolset-11/enable
which gcc
gcc --version
```

确认是 GCC 11 后，再从“阶段四：在独立目录配置构建”的配置命令开始。源码目录和已经下载的
GMP、MPFR、MPC、isl 不需要重新下载。

### 14.2 `gnu/stubs-32.h: No such file`

原因：配置时尝试构建 32 位 multilib。

检查配置命令是否包含：

```text
--disable-multilib
```

修正配置后应使用一个新的、空的构建目录重新配置，不能只在旧目录反复运行不同参数。

### 14.3 `GMP/MPFR/MPC is missing`

原因通常是 `contrib/download_prerequisites` 没有成功完成。

检查：

```bash
cd /home/ratis/toolchains/src/gcc-14.3.0
ls -ld gmp mpfr mpc isl
```

缺少任何一个都先重新处理依赖下载。

### 14.4 Maven 仍然报告旧的 GLIBCXX/CXXABI

按顺序执行：

```bash
source "$HOME/.gcc-14.3.0-env"
echo "$LD_LIBRARY_PATH"
g++ -print-file-name=libstdc++.so.6
ldd ratis-proto/target/protoc-plugins/protoc-gen-grpc-java-1.77.1-linux-x86_64.exe \
  | grep libstdc++
```

`gcc --version` 是 14.3.0，但 `ldd` 仍指向 `/lib64/libstdc++.so.6`，说明问题在运行时动态库搜索路径，
不是编译器命令版本。

### 14.5 新 SSH 窗口又变回 GCC 4.8.5

先手工执行：

```bash
source "$HOME/.gcc-14.3.0-env"
```

然后检查 `.bashrc` 是否包含自动加载行。注意 root 和普通用户拥有不同的 `$HOME`，环境文件不会跨用户自动生效。

## 15. 最终验收清单

每台机器都应能提供以下证据：

```text
[ ] uname -m 是 x86_64
[ ] /usr/bin/gcc 没有被覆盖
[ ] /lib64/libstdc++.so.6 没有被手动替换
[ ] /usr/local/gcc-14.3.0/bin/gcc --version 显示 14.3.0
[ ] g++ -print-file-name=libstdc++.so.6 指向 /usr/local/gcc-14.3.0
[ ] 新 libstdc++ 包含 GLIBCXX_3.4.21、CXXABI_1.3.8、CXXABI_1.3.9
[ ] ldd protoc-gen-grpc-java 指向 /usr/local/gcc-14.3.0/lib64/libstdc++.so.6
[ ] Maven package 成功
[ ] ratis-examples 可执行 JAR 存在
```

只有 node1 完成以上验收后，再开始 node2、node3。

## 16. 官方资料

- GCC 14.3.0 官方发布目录：<https://gcc.gnu.org/pub/gcc/releases/gcc-14.3.0/>
- GCC 构建前置要求：<https://gcc.gnu.org/install/prerequisites.html>
- GCC 配置说明：<https://gcc.gnu.org/install/configure.html>
- GCC 构建说明：<https://gcc.gnu.org/install/build.html>
- GCC 安装说明：<https://gcc.gnu.org/install/finalinstall.html>
