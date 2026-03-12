#!/usr/bin/env python3

import socket
import struct
import os
import time

MAGIC_COOKIE = 0x2112A442

STUN_SERVERS = [
    ("stun.l.google.com", 19302),
    ("stun.cloudflare.com", 3478),
    ("stun.twilio.com", 3478),
    ("stun.nextcloud.com", 3478),
]


def build_request():
    msg_type = 0x0001  # Binding Request
    msg_len = 0
    transaction_id = os.urandom(12)

    header = struct.pack("!HHI12s", msg_type, msg_len, MAGIC_COOKIE, transaction_id)

    return header, transaction_id


def parse_response(data, transaction_id):

    msg_type, msg_len, cookie = struct.unpack("!HHI", data[:8])
    recv_tx = data[8:20]

    if recv_tx != transaction_id:
        return None

    pos = 20

    while pos < len(data):

        attr_type, attr_len = struct.unpack("!HH", data[pos:pos+4])
        pos += 4

        attr_data = data[pos:pos+attr_len]

        if attr_type == 0x0020:  # XOR-MAPPED-ADDRESS

            family = attr_data[1]

            xport = struct.unpack("!H", attr_data[2:4])[0]
            port = xport ^ (MAGIC_COOKIE >> 16)

            if family == 0x01:  # IPv4

                xip = struct.unpack("!I", attr_data[4:8])[0]
                ip = socket.inet_ntoa(struct.pack("!I", xip ^ MAGIC_COOKIE))

                return ip, port

        pos += attr_len

    return None


def stun_query(server, port, timeout=3):

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)

    req, tx = build_request()

    try:
        sock.sendto(req, (server, port))
        data, _ = sock.recvfrom(2048)

        return parse_response(data, tx)

    except Exception:
        return None

    finally:
        sock.close()


def main():

    print("=== Simple NAT Diagnostic ===\n")

    results = []

    for host, port in STUN_SERVERS:

        print(f"Testing {host}:{port}")

        res = stun_query(host, port)

        if res:
            ip, ext_port = res
            print(f"  External: {ip}:{ext_port}")

            results.append(ext_port)

        else:
            print("  Failed")

        time.sleep(0.5)

    print("\n=== Analysis ===")

    if not results:
        print("No STUN responses received.")
        return

    if len(set(results)) > 1:
        print("External port varies across servers.")
        print("Likely NAT: Symmetric NAT")
    else:
        print("External port stable across servers.")
        print("Likely NAT: Cone / Restricted NAT")

    print("\nPorts observed:", results)


if __name__ == "__main__":
    main()
