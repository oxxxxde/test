#!/bin/bash

echo "======================================================"
echo "🚀 开始一键部署 原生 Python SOCKS5 (终极兼容老版本)"
echo "======================================================"

# 1. 强制清理旧文件，防止缓存覆盖失败
rm -f main.py

# 2. 检查环境
if ! command -v python3 &> /dev/null; then
    echo "未检测到 Python3，正在尝试自动安装..."
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y python3
    elif command -v yum &> /dev/null; then
        yum install -y python3
    else
        echo "❌ 无法自动安装 Python3，请手动安装后重试。"
        exit 1
    fi
fi

# 3. 动态生成纯 Python SOCKS5 服务端代码 (彻底移除所有 3.7+ 语法)
echo "📝 正在生成主程序文件 main.py..."
cat << 'EOF' > main.py
import asyncio
import os
import struct
import socket
import base64

# 硬编码指定的账号密码
USER = "8EMS7iXE"
PASS = "PiEyhTaxVkxA"
DOMAIN = os.environ.get("DOMAIN", "kele-1.paiza-user-free.cloud")
PORT = int(os.environ.get("PORT", "6789"))

async def pipe(reader, writer):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except Exception:
        pass
    finally:
        writer.close()

async def handle_client(reader, writer):
    try:
        version_nmethods = await reader.readexactly(2)
        version, nmethods = struct.unpack("!BB", version_nmethods)
        methods = await reader.readexactly(nmethods)
        
        if version != 5 or 2 not in methods:
            writer.write(b"\x05\xFF")
            await writer.drain()
            return
        writer.write(b"\x05\x02")
        await writer.drain()

        auth_req = await reader.readexactly(2)
        ulen = auth_req[1]
        uname = (await reader.readexactly(ulen)).decode()
        
        plen_buf = await reader.readexactly(1)
        plen = plen_buf[0]
        upass = (await reader.readexactly(plen)).decode()

        if uname == USER and upass == PASS:
            writer.write(b"\x01\x00")
            await writer.drain()
        else:
            writer.write(b"\x01\x01")
            await writer.drain()
            return

        req_header = await reader.readexactly(4)
        ver, cmd, rsv, atyp = req_header

        # 拒绝 UDP，强制 TCP 链式代理
        if cmd == 3:
            writer.write(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00")
            await writer.drain()
            return
        elif cmd != 1:
            return

        if atyp == 1:
            dst_addr = socket.inet_ntoa(await reader.readexactly(4))
        elif atyp == 3:
            domain_len = (await reader.readexactly(1))[0]
            dst_addr = (await reader.readexactly(domain_len)).decode()
        elif atyp == 4:
            dst_addr = socket.inet_ntop(socket.AF_INET6, await reader.readexactly(16))
        else:
            return

        dst_port = struct.unpack("!H", await reader.readexactly(2))[0]

        try:
            remote_reader, remote_writer = await asyncio.open_connection(dst_addr, dst_port)
            writer.write(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
            await writer.drain()
        except Exception:
            writer.write(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00") 
            await writer.drain()
            return

        # 彻底移除 create_task，改用兼容所有老版本的 ensure_future
        task_c2r = asyncio.ensure_future(pipe(reader, remote_writer))
        task_r2c = asyncio.ensure_future(pipe(remote_reader, writer))
        await asyncio.gather(task_c2r, task_r2c)

    except Exception:
        pass
    finally:
        writer.close()

async def main():
    server = await asyncio.start_server(handle_client, '0.0.0.0', PORT)
    
    auth_str = "{}:{}".format(USER, PASS)
    auth_b64 = base64.b64encode(auth_str.encode()).decode().rstrip('=')
    share_link = "socks://{}@{}:{}".format(auth_b64, DOMAIN, PORT)

    print("\n======================================================")
    print("✅ 纯 Python 原生 SOCKS5 已启动 (终极老系统兼容版)")
    print("======================================================")
    print("🌐 节点地址: {}".format(DOMAIN))
    print("🔌 监听端口: {}".format(PORT))
    print("👤 固定用户名: {}".format(USER))
    print("🔑 固定密码: {}".format(PASS))
    print("------------------------------------------------------")
    print("📌 客户端订阅/导入链接:")
    print(share_link)
    print("======================================================\n")

    if hasattr(server, 'serve_forever'):
        await server.serve_forever()
    else:
        while True:
            await asyncio.sleep(3600)

if __name__ == "__main__":
    try:
        # 彻底移除 asyncio.run，全版本兼容启动方式
        loop = asyncio.get_event_loop()
        loop.run_until_complete(main())
    except KeyboardInterrupt:
        pass
EOF
echo "✅ main.py 创建成功！"

# 4. 运行服务
if [ "$(id -u)" -eq 0 ] && command -v systemctl &> /dev/null; then
    echo "🔧 正在注册为 Systemd 后台守护进程..."
    cat << EOF > /etc/systemd/system/pysocks5.service
[Unit]
Description=Lightweight Python SOCKS5 Proxy
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$(pwd)
ExecStart=$(command -v python3) $(pwd)/main.py
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable pysocks5
    systemctl restart pysocks5
    echo "✅ 服务已在后台永久运行！命令: systemctl status pysocks5"
    sleep 1
    systemctl status pysocks5 --no-pager | grep "socks://"
else
    echo "▶️ 普通权限环境，正在前台启动服务..."
    python3 main.py
fi
