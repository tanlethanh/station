#!/usr/bin/env python3

import socket
import time
import statistics
import subprocess
import json
import ipaddress
import requests
import click
import math


# -----------------------------
# Test endpoints
# -----------------------------

TEST_ENDPOINTS = {
    "sg": {
        "host": "speedtest.singapore.linode.com",
        "download": "http://speedtest.singapore.linode.com/100MB-singapore.bin",
        "upload": "http://speedtest.singapore.linode.com"
    },
    "eu": {
        "host": "speedtest.frankfurt.linode.com",
        "download": "http://speedtest.frankfurt.linode.com/100MB-frankfurt.bin",
        "upload": "http://speedtest.frankfurt.linode.com"
    },
    "us": {
        "host": "speedtest.dallas.linode.com",
        "download": "http://speedtest.dallas.linode.com/100MB-dallas.bin",
        "upload": "http://speedtest.dallas.linode.com"
    }
}


REGION_COORDS = {
    "sg": (1.290270, 103.851959),
    "eu": (50.110924, 8.682127),
    "us": (32.776665, -96.796989)
}


# -----------------------------
# Network identity
# -----------------------------

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return None


def get_public_ip():

    services = [
        "https://api.ipify.org?format=json",
        "https://ifconfig.me/all.json"
    ]

    for url in services:
        try:
            r = requests.get(url, timeout=3)
            data = r.json()

            if "ip" in data:
                return data["ip"]

            if "ip_addr" in data:
                return data["ip_addr"]

        except:
            pass

    return None


def detect_nat(local_ip, public_ip):

    if not local_ip or not public_ip:
        return "unknown"

    local = ipaddress.ip_address(local_ip)

    if local.is_private:
        return "behind_nat"

    if local_ip != public_ip:
        return "possible_nat"

    return "public_ip"


def detect_cgnat(ip):

    try:
        net = ipaddress.ip_network("100.64.0.0/10")
        return ipaddress.ip_address(ip) in net
    except:
        return False


# -----------------------------
# Geo IP (ipinfo)
# -----------------------------

def get_geo_info(ip=None):

    try:

        url = "https://ipinfo.io/json"
        if ip:
            url = f"https://ipinfo.io/{ip}/json"

        r = requests.get(url, timeout=4)
        data = r.json()

        loc = data.get("loc", "")

        lat = None
        lon = None

        if loc:
            parts = loc.split(",")
            lat = float(parts[0])
            lon = float(parts[1])

        return {
            "country": data.get("country"),
            "region": data.get("region"),
            "city": data.get("city"),
            "lat": lat,
            "lon": lon,
            "isp": data.get("org"),
            "hostname": data.get("hostname")
        }

    except:
        return None


# -----------------------------
# Distance calculation
# -----------------------------

def distance_km(lat1, lon1, lat2, lon2):

    R = 6371

    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)

    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )

    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c


# -----------------------------
# Latency test
# -----------------------------

def tcp_ping(host, port=80, attempts=5):

    times = []

    for _ in range(attempts):

        start = time.time()

        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)

        try:
            sock.connect((host, port))
            latency = (time.time() - start) * 1000
            times.append(latency)

        except:
            pass

        finally:
            sock.close()

    if not times:
        return None

    return {
        "avg": round(statistics.mean(times), 2),
        "min": round(min(times), 2),
        "max": round(max(times), 2)
    }


# -----------------------------
# Download test
# -----------------------------

def download_test(url, limit_mb=50):

    start = time.time()

    r = requests.get(url, stream=True)

    size = 0

    for chunk in r.iter_content(65536):

        size += len(chunk)

        if size >= limit_mb * 1024 * 1024:
            break

    duration = time.time() - start

    mbps = (size * 8) / duration / 1_000_000

    return round(mbps, 2)


# -----------------------------
# Upload test
# -----------------------------

def upload_test(url, size_mb=20):

    data = b"x" * (size_mb * 1024 * 1024)

    start = time.time()

    try:
        requests.post(url, data=data, timeout=30)
    except:
        return None

    duration = time.time() - start

    mbps = (len(data) * 8) / duration / 1_000_000

    return round(mbps, 2)


# -----------------------------
# Traceroute
# -----------------------------

def traceroute(host):

    try:

        result = subprocess.run(
            ["traceroute", "-m", "15", host],
            capture_output=True,
            text=True
        )

        return result.stdout

    except:
        return "Traceroute failed"


# -----------------------------
# CLI
# -----------------------------

@click.command()
@click.option("--region", default="all", help="sg | eu | us | all")
@click.option("--trace", is_flag=True, help="run traceroute")
@click.option("--json-output", is_flag=True)
def run(region, trace, json_output):

    results = {}

    local_ip = get_local_ip()
    public_ip = get_public_ip()

    nat = detect_nat(local_ip, public_ip)
    cgnat = detect_cgnat(public_ip)

    geo = get_geo_info(public_ip)

    identity = {
        "local_ip": local_ip,
        "public_ip": public_ip,
        "nat": nat,
        "cgnat": cgnat,
        "geo": geo
    }

    if not json_output:

        print("\n=== Network Identity ===")
        print("Local IP :", local_ip)
        print("Public IP:", public_ip)
        print("NAT      :", nat)

        if cgnat:
            print("CGNAT    : detected")

        if geo:
            print("\nLocation:")
            print("  Country :", geo["country"])
            print("  Region  :", geo["region"])
            print("  City    :", geo["city"])
            print("  ISP     :", geo["isp"])

    regions = TEST_ENDPOINTS.keys() if region == "all" else [region]

    for r in regions:

        cfg = TEST_ENDPOINTS[r]

        if not json_output:
            print(f"\n=== Testing {r.upper()} ===")

        latency = tcp_ping(cfg["host"])
        download = download_test(cfg["download"])
        upload = upload_test(cfg["upload"])

        dist = None

        if geo and geo["lat"]:
            region_lat, region_lon = REGION_COORDS[r]

            dist = distance_km(
                geo["lat"],
                geo["lon"],
                region_lat,
                region_lon
            )

        region_result = {
            "latency": latency,
            "download_mbps": download,
            "upload_mbps": upload,
            "distance_km": round(dist, 1) if dist else None
        }

        if trace:
            region_result["traceroute"] = traceroute(cfg["host"])

        results[r] = region_result

        if not json_output:

            if dist:
                print("Distance :", round(dist, 1), "km")

            print("Latency  :", latency)
            print("Download :", download, "Mbps")
            print("Upload   :", upload, "Mbps")

    output = {
        "identity": identity,
        "regions": results
    }

    if json_output:
        print(json.dumps(output, indent=2))


if __name__ == "__main__":
    run()
