#!/bin/bash

# 脚本保存路径
SCRIPT_PATH="$HOME/Ocean.sh"

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 检查并安装 Docker 和 Docker Compose
function install_docker_and_compose() {
    # 检查是否已安装 Docker
    if ! command -v docker &> /dev/null; then
        echo "Docker 未安装，正在安装 Docker..."

        # 安装 Docker 和依赖
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        sudo systemctl start docker
        sudo systemctl enable docker
    else
        echo "Docker 已安装，跳过安装步骤。"
    fi

    # 验证 Docker 状态
    echo "Docker 状态:"
    sudo systemctl status docker --no-pager

    # 检查是否已安装 Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose 未安装，正在安装 Docker Compose..."
        DOCKER_COMPOSE_VERSION="2.20.2"
        sudo curl -L "https://github.com/docker/compose/releases/download/v$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    else
        echo "Docker Compose 已安装，跳过安装步骤。"
    fi

    # 输出 Docker Compose 版本
    echo "Docker Compose 版本:"
    docker-compose --version
}

# 生成私钥并计算对应的EVM地址
function generate_private_keys() {
    # 创建存储私钥的目录
    mkdir -p ocean-private-key
    cd ocean-private-key || { echo "无法进入目录"; exit 1; }

    # 提示用户输入要生成的私钥数量
    echo -n "请输入要生成的私钥数量: "
    read -r key_count

    for ((i = 1; i <= key_count; i++)); do
        # 生成私钥
        private_key=$(openssl ecparam -name secp256k1 -genkey -noout | openssl ec -text -noout | grep -A5 "priv:" | grep -v "priv:" | tr -d '\n[:space:]')

        # 生成公钥
        public_key=$(echo -n "$private_key" | openssl ec -pubout -conv_form compressed -outform DER 2>/dev/null | tail -c 33 | xxd -p -c 33)

        # 生成EVM地址 (使用Keccak-256哈希算法)
        evm_address=$(echo -n "$public_key" | keccak-256sum -x -l | tr -d ' -' | tail -c 41)

        # 保存私钥和对应的地址
        echo "0x$private_key" > "private_key_$i.txt"
        echo "0x$evm_address" >> "private_key_$i.txt"
        echo "生成的私钥和地址保存至 ocean-private-key/private_key_$i.txt"
    done
}

# 设置并启动节点
function setup_and_start_node() {
    # 提示用户输入要启动的节点数量
    echo -n "请输入要启动的节点数量: "
    read -r node_count

    # 提示用户输入起始端口
    echo -n "请输入起始端口号: "
    read -r start_port

    # 创建目录并进入
    mkdir -p ocean
    cd ocean || { echo "无法进入目录"; exit 1; }

    # 下载节点脚本并赋予执行权限
    curl -fsSL -O https://raw.githubusercontent.com/candy1264/ocean/main/ocean-node-quickstart.sh?token=GHSAT0AAAAAACTUA5SYXJEVGGLK5GG7JKGGZXAMI3A
    chmod +x ocean-node-quickstart.sh

    # 启动节点
    for ((i = 0; i < node_count; i++)); do
        port=$((start_port + i))
        echo "正在启动端口 $port 上的节点..."
        PRIVATE_KEY_FILE="../ocean-private-key/private_key_$((i+1)).txt"
        PRIVATE_KEY=$(sed -n '1p' "$PRIVATE_KEY_FILE")
        ./ocean-node-quickstart.sh -p "$port" -k "$PRIVATE_KEY" &
    done

    echo "$node_count 个节点启动完成！"
}

function view_logs() {
    echo "查看 Docker 日志..."
    if [ -d "/root/ocean" ]; then
        cd /root/ocean && docker-compose logs -f || { echo "无法查看 Docker 日志"; exit 1; }
    else
        echo "请先启动节点，目录 '/root/ocean' 不存在。"
    fi
}

# 主菜单函数
function main_menu() {
    while true; do
        clear
        echo "脚本由大赌社区哈哈哈哈编写，推特 @ferdie_jhovie，免费开源，请勿相信收费"
        echo "如有问题，可联系推特，仅此只有一个号"
        echo "================================================================"
        echo "退出脚本，请按键盘 ctrl + C 退出即可"
        echo "请选择要执行的操作:"
        echo "1. 生成私钥"
        echo "2. 启动节点"
        echo "3. 查看日志"
        echo "4. 退出"
        echo -n "请输入选项 (1/2/3/4): "
        read -r choice

        case $choice in
            1)
                echo "正在生成私钥..."
                generate_private_keys
                read -p "操作完成。按任意键返回主菜单。" -n1 -s
                ;;
            2)
                echo "正在启动节点..."
                install_docker_and_compose
                setup_and_start_node
                read -p "操作完成。按任意键返回主菜单。" -n1 -s
                ;;
            3)
                view_logs
                read -p "按任意键返回主菜单。" -n1 -s
                ;;
            4)
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效选项，请选择 1、2、3 或 4。"
                ;;
        esac
    done
}

# 执行主菜单
main_menu
