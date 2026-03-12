// server.js

const http = require("http");
const https = require("https");
const os = require("os");
const natUpnp = require("nat-upnp");

const LOCAL_PORT = 3000;
const PUBLIC_PORT = 8080;

/* -----------------------------
   Get local network IPs
----------------------------- */

function getLocalIPs() {
  const nets = os.networkInterfaces();
  const ips = [];

  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === "IPv4" && !net.internal) {
        ips.push(net.address);
      }
    }
  }

  return ips;
}

/* -----------------------------
   Query ifconfig.me
----------------------------- */

function getPublicInfo() {
  return new Promise((resolve) => {

    https.get("https://ifconfig.me/all.json", (res) => {

      let data = "";

      res.on("data", chunk => data += chunk);

      res.on("end", () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          resolve(null);
        }
      });

    }).on("error", () => resolve(null));

  });
}

/* -----------------------------
   Setup UPnP port forwarding
----------------------------- */

const upnp = natUpnp.createClient();

upnp.portMapping(
  {
    public: PUBLIC_PORT,
    private: LOCAL_PORT,
    ttl: 3600
  },
  (err) => {

    if (err) {
      console.log("UPnP mapping failed:", err.message);
    } else {
      console.log(`UPnP port mapping: ${PUBLIC_PORT} -> ${LOCAL_PORT}`);
    }

  }
);

/* -----------------------------
   HTTP Server
----------------------------- */

const server = http.createServer((req, res) => {

  const ip = req.socket.remoteAddress;
  const port = req.socket.remotePort;
  const time = new Date().toISOString();

  console.log(`[${time}] ${ip}:${port} ${req.method} ${req.url}`);

  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("Hello from Node server\n");

});

server.on("connection", socket => {
  console.log(`TCP connection from ${socket.remoteAddress}:${socket.remotePort}`);
});

/* -----------------------------
   Start server
----------------------------- */

server.listen(LOCAL_PORT, "0.0.0.0", async () => {

  console.log(`Server running on 0.0.0.0:${LOCAL_PORT}`);

  const localIPs = getLocalIPs();

  console.log("\nLocal network addresses:");

  localIPs.forEach(ip => {
    console.log(`  http://${ip}:${LOCAL_PORT}`);
  });

  console.log("\nFetching public network info...\n");

  const info = await getPublicInfo();

  if (info) {

    console.log("Public network info:");

    console.log("  Public IP:", info.ip_addr);
    console.log("  NAT external port:", info.port);
    console.log("  User-Agent:", info.user_agent);

    console.log(`\nPublic address (expected):`);
    console.log(`  http://${info.ip_addr}:${PUBLIC_PORT}`);

  } else {

    console.log("Could not fetch public IP info");

  }

  console.log("\nWaiting for connections...\n");

});
