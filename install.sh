#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}致命错误: ${plain} 请使用 root 权限运行此脚本\n" && exit 1

# ================== 仓库 raw 地址 ==================
REPO_RAW="https://raw.githubusercontent.com/BLACK-ARCHIVERS/X-Panel-2025/main"
# ===================================================

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64 ) echo 'amd64' ;;
        i*86 | x86 ) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        armv7* | armv7 | arm ) echo 'armv7' ;;
        armv6* | armv6 ) echo 'armv6' ;;
        armv5* | armv5 ) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo 'amd64' ;;
    esac
}

echo ""
echo -e "${green}---------->>>>>安装开始${plain}"
echo -e "${yellow}---------->>>>>当前架构: $(arch)${plain}"

# 读取版本号（读不到就用 local）
last_version=$(curl -Ls "${REPO_RAW}/VERSION" 2>/dev/null | tr -d '\r\n')
[[ -z "$last_version" ]] && last_version="local"
echo -e "${yellow}---------->>>>>版本号: ${last_version}${plain}"

# ================== 基础依赖安装（探测包管理器，不区分发行版） ==================
install_base() {
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -q wget curl sudo tar tzdata
    elif command -v yum &>/dev/null; then
        yum install -y -q wget curl sudo tar tzdata
    elif command -v dnf &>/dev/null; then
        dnf install -y -q wget curl sudo tar tzdata
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm wget curl sudo tar tzdata
    elif command -v apk &>/dev/null; then
        apk update && apk add --no-cache wget curl sudo tar tzdata
    fi
}

gen_random_string() {
    local length="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1
}

config_after_install() {
    echo ""
    echo -e "${yellow}安装完成！建议修改面板登录信息${plain}"
    read -p "$(echo -e "${green}是否修改？${red}输入 n 保留随机生成的登录信息${plain} [y/n]: ")" config_confirm
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        read -p "请设置用户名: " config_account
        read -p "请设置密码: " config_password
        read -p "请设置面板端口: " config_port
        read -p "请设置面板访问路径: " config_webBasePath
        /usr/local/x-ui/x-ui setting -username "${config_account}" -password "${config_password}"
        /usr/local/x-ui/x-ui setting -port "${config_port}"
        /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}"
        echo -e "${green}登录信息设置成功${plain}"
    else
        if [[ ! -f "/etc/x-ui/x-ui.db" ]]; then
            local usernameTemp=$(head -c 10 /dev/urandom | base64)
            local passwordTemp=$(head -c 10 /dev/urandom | base64)
            local webBasePathTemp=$(gen_random_string 15)
            /usr/local/x-ui/x-ui setting -username "${usernameTemp}" -password "${passwordTemp}" -webBasePath "${webBasePathTemp}"
            echo ""
            echo -e "${yellow}已生成随机登录信息：${plain}"
            echo -e "###############################################"
            echo -e "${green}用户名: ${usernameTemp}${plain}"
            echo -e "${green}密  码: ${passwordTemp}${plain}"
            echo -e "${green}访问路径: ${webBasePathTemp}${plain}"
            echo -e "###############################################"
        else
            echo -e "${green}检测到已有配置，保留旧设置${plain}"
        fi
    fi
    sleep 1
    /usr/local/x-ui/x-ui migrate 2>/dev/null
}

install_x-ui() {
    cd /usr/local/

    echo ""
    echo -e "${green}------->>开始下载并安装 X-Panel ${last_version}${plain}"

    # 下载二进制（直接从 raw 拉，不走 releases API）
    wget -N --no-check-certificate -O /usr/local/x-ui-linux-$(arch).tar.gz "${REPO_RAW}/x-ui-linux-$(arch).tar.gz"
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 x-ui-linux-$(arch).tar.gz 失败，请确认仓库根目录已上传该文件${plain}"
        exit 1
    fi

    # 下载 x-ui.sh 管理脚本
    wget -O /usr/bin/x-ui-temp "${REPO_RAW}/x-ui.sh"
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 x-ui.sh 失败${plain}"
        exit 1
    fi

    # 清理旧版本
    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui 2>/dev/null
        rm -rf /usr/local/x-ui/
    fi

    echo -e "${green}------->>解压安装包${plain}"
    tar zxvf x-ui-linux-$(arch).tar.gz
    rm -f x-ui-linux-$(arch).tar.gz

    cd x-ui
    chmod +x x-ui x-ui.sh 2>/dev/null

    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm 2>/dev/null
        chmod +x bin/xray-linux-arm 2>/dev/null
    fi
    chmod +x x-ui bin/xray-linux-$(arch) 2>/dev/null

    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui

    # 处理登录信息
    config_after_install

    # 安装 systemd 服务
    if [[ -f x-ui.service ]]; then
        cp -f x-ui.service /etc/systemd/system/
    else
        cat > /etc/systemd/system/x-ui.service <<EOF
[Unit]
Description=x-ui Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/usr/local/x-ui/
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable x-ui 2>/dev/null
    systemctl start x-ui

    sleep 2
    echo ""
    echo -e "${yellow}----->>>X-Panel 面板和 Xray 已启动<<<-----${plain}"
}

# 时区设置（失败不阻断）
timedatectl set-timezone Asia/Shanghai 2>/dev/null

install_base
install_x-ui

echo ""
echo -e "${green}================= 安装完成 =================${plain}"
echo ""
/usr/local/x-ui/x-ui setting -show true 2>/dev/null
echo ""
echo -e "${yellow}若忘记登录信息，执行 x-ui 后选择数字 [10] 查看${plain}"
echo ""
echo -e "${green}项目地址：https://github.com/BLACK-ARCHIVERS/X-Panel-2025${plain}"
echo ""
