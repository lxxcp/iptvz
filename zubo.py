from threading import Thread
import os
import time
import datetime
import glob
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed


def is_ipv4(s):
    """判断字符串是否是合法的 IPv4 地址"""
    parts = s.split('.')
    if len(parts) != 4:
        return False
    return all(p.isdigit() and 0 <= int(p) <= 255 for p in parts)


def parse_ip_port(entry):
    """尝试把 'a.b.c.d:port' 解析成 (ip, port)；失败返回 None（说明是域名或非法行）"""
    try:
        ip, port = entry.rsplit(':', 1)
        if is_ipv4(ip):
            return ip, port
    except Exception:
        pass
    return None


def read_config(config_file):
    print(f"读取设置文件：{config_file}")
    ip_configs = []
    try:
        with open(config_file, 'r') as f:
            for line_num, line in enumerate(f, 1):
                if "," in line and not line.startswith("#"):
                    parts = line.strip().split(',')
                    try:
                        ip_part, port = parts[0].strip().split(':')
                        # 若是域名（如 ai.xiaoshudiao.top）则跳过，不参与扫描
                        if not is_ipv4(ip_part):
                            print(f"第{line_num}行非IPv4地址，跳过：{line.strip()}")
                            continue
                        a, b, c, d = ip_part.split('.')
                        option = int(parts[1])
                        url_end = "/status" if option >= 10 else "/stat"
                        ip = f"{a}.{b}.{c}.1" if option % 2 == 0 else f"{a}.{b}.1.1"
                        ip_configs.append((ip, port, option, url_end))
                        print(f"第{line_num}行：http://{ip}:{port}{url_end}添加到扫描列表")
                    except (ValueError, IndexError) as e:
                        print(f"第{line_num}行格式错误，跳过：{line.strip()}  ({e})")
                        continue
        return ip_configs
    except Exception as e:
        print(f"读取文件错误: {e}")
        return ip_configs


def generate_ip_ports(ip, port, option):
    a, b, c, d = ip.split('.')
    if option == 2 or option == 12:
        c_extent = c.split('-')
        c_first = int(c_extent[0]) if len(c_extent) == 2 else int(c)
        c_last = int(c_extent[1]) + 1 if len(c_extent) == 2 else int(c) + 8
        return [f"{a}.{b}.{x}.{y}:{port}" for x in range(c_first, c_last) for y in range(1, 256)]
    elif option == 0 or option == 10:
        return [f"{a}.{b}.{c}.{y}:{port}" for y in range(1, 256)]
    else:
        return [f"{a}.{b}.{x}.{y}:{port}" for x in range(256) for y in range(1, 256)]


def check_ip_port(ip_port, url_end):
    try:
        url = f"http://{ip_port}{url_end}"
        resp = requests.get(url, timeout=2)
        resp.raise_for_status()
        if "Multi stream daemon" in resp.text or "udpxy status" in resp.text:
            print(f"{url} 访问成功")
            return ip_port
    except Exception:
        return None


def scan_ip_port(ip, port, option, url_end):
    def show_progress():
        while checked[0] < len(ip_ports) and option % 2 == 1:
            print(f"已扫描：{checked[0]}/{len(ip_ports)}, 有效ip_port：{len(valid_ip_ports)}个")
            time.sleep(30)

    valid_ip_ports = []
    ip_ports = generate_ip_ports(ip, port, option)
    checked = [0]
    Thread(target=show_progress, daemon=True).start()
    with ThreadPoolExecutor(max_workers=300 if option % 2 == 1 else 100) as executor:
        futures = {executor.submit(check_ip_port, ip_port, url_end): ip_port for ip_port in ip_ports}
        for future in as_completed(futures):
            result = future.result()
            if result:
                valid_ip_ports.append(result)
            checked[0] += 1
    return valid_ip_ports


def multicast_province(config_file):
    filename = os.path.basename(config_file)
    province = filename.split('_')[0]
    print(f"{'='*25}\n   获取: {province}ip_port\n{'='*25}")
    configs = sorted(set(read_config(config_file)))
    print(f"读取完成，共需扫描 {len(configs)}组")

    ip_file = f"ip/{province}_ip.txt"

    # === 修复点①：读取原文件中保留的非 IP 条目（如域名） ===
    preserved = []
    if os.path.exists(ip_file):
        with open(ip_file, 'r', encoding='utf-8') as f:
            for line in f:
                entry = line.strip()
                if not entry:
                    continue
                if parse_ip_port(entry) is None:
                    preserved.append(entry)
    if preserved:
        print(f"检测到 {len(preserved)} 条非IP条目，将予以保留：")
        for p in preserved:
            print(f"  · {p}")

    all_ip_ports = []
    for ip, port, option, url_end in configs:
        print(f"\n开始扫描  http://{ip}:{port}{url_end}")
        all_ip_ports.extend(scan_ip_port(ip, port, option, url_end))

    # === 修复点②：合并扫描结果 + 保留的域名条目再写回文件 ===
    merged = sorted(set(all_ip_ports) | set(preserved))

    if len(all_ip_ports) != 0 or preserved:
        print(f"\n{province} 扫描完成，获取有效条目共：{len(merged)}个\n{merged}\n")
        with open(ip_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(merged))

        # === 修复点③：存档处理时安全跳过域名条目 ===
        archive_file = f"ip/存档_{province}_ip.txt"
        if os.path.exists(archive_file):
            with open(archive_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            for ip_port in all_ip_ports:  # 只用纯 IP 结果生成存档，不含域名
                parsed = parse_ip_port(ip_port)
                if parsed is None:
                    continue
                ip, port = parsed
                a, b, c, d = ip.split(".")
                lines.append(f"{a}.{b}.{c}.1:{port}\n")
            lines = sorted(set(lines))
            with open(archive_file, 'w', encoding='utf-8') as f:
                f.writelines(lines)

        # 生成组播 txt（域名条目同样能通过 replace 填进模板，不会出错）
        template_file = os.path.join('template', f"template_{province}.txt")
        if os.path.exists(template_file):
            with open(template_file, 'r', encoding='utf-8') as f:
                tem_channels = f.read()
            output = []
            with open(ip_file, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f, 1):
                    ip = line.strip()
                    output.append(f"{province}-组播{line_num},#genre#\n")
                    output.append(tem_channels.replace("ipipip", f"{ip}"))
            with open(f"组播_{province}.txt", 'w', encoding='utf-8') as f:
                f.writelines(output)
        else:
            print(f"缺少模板文件: {template_file}")
    else:
        print(f"\n{province} 扫描完成，未扫描到有效ip_port")


def txt_to_m3u(input_file, output_file):
    with open(input_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    with open(output_file, 'w', encoding='utf-8') as f:
        genre = ''
        for line in lines:
            line = line.strip()
            if "," in line:
                channel_name, channel_url = line.split(',', 1)
                if channel_url == '#genre#':
                    genre = channel_name
                else:
                    f.write(f'#EXTINF:-1 group-title="{genre}",{channel_name}\n')
                    f.write(f'{channel_url}\n')


def main():
    for config_file in glob.glob(os.path.join('ip', '*_config.txt')):
        multicast_province(config_file)

    file_contents = []
    for file_path in glob.glob('组播_*电信.txt'):
        with open(file_path, 'r', encoding="utf-8") as f:
            file_contents.append(f.read())
    for file_path in glob.glob('组播_*联通.txt'):
        with open(file_path, 'r', encoding="utf-8") as f:
            file_contents.append(f.read())
    for file_path in glob.glob('组播_*移动.txt'):
        with open(file_path, 'r', encoding="utf-8") as f:
            file_contents.append(f.read())

    now = datetime.datetime.now(datetime.UTC) + datetime.timedelta(hours=8)
    current_time = now.strftime("%Y/%m/%d %H:%M")
    with open("zubo_all.txt", "w", encoding="utf-8") as f:
        f.write(f"{current_time}更新,#genre#\n")
        f.write(f"浙江卫视,http://ali-m-l.cztv.com/channels/lantian/channel001/1080p.m3u8\n")
        f.write('\n'.join(file_contents))

    txt_to_m3u("zubo_all.txt", "zubo_all.m3u")
    print(f"组播地址获取完成")


if __name__ == "__main__":
    main()