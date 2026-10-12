# ═══════════════════════════════════════════════════════════════════════
#  BATCH 4: NETWORKING
# ═══════════════════════════════════════════════════════════════════════

# ── NETWORK ───────────────────────────────────────────────────────────

network
#   🌐 Network
#   ├─ WiFi      ◉ "HomeNetwork"  78% (-52 dBm)  867 Mbps  WPA3
#   ├─ Ethernet  ✗ Disconnected
#   ├─ IP        192.168.1.42
#   ├─ DNS       1.1.1.1, 8.8.8.8
#   └─ Bandwidth 2.3 MB/s ↓  0.1 MB/s ↑

network info                        → full network state
network connected                   → true/false
network type                        → "wifi", "ethernet", "both", "none"
network interfaces                  → list all interfaces
network interface wlan0             → interface summary
network interface wlan0 info        → full details
network interface wlan0 enable      → enable
network interface wlan0 disable     → disable
network interface wlan0 mtu 1400    → set MTU
network wifi                        → WiFi status
network wifi on                     → enable WiFi
network wifi off                    → disable WiFi
network wifi scan                   → scan networks
network wifi connect "HomeNetwork" "password123"  → connect
network wifi connect "HomeNetwork" "password123" --band 5ghz  → force band
network wifi connect "Hidden" "pass" --hidden  → hidden network
network wifi disconnect             → disconnect
network wifi forget "OldNetwork"    → forget
network wifi saved                  → saved networks
network wifi signal                 → signal strength
network wifi speed                  → connection speed
network wifi security               → security type
network wifi channel                → channel
network wifi band                   → band
network wifi bssid                  → AP MAC
network wifi set-auto-connect "Home" on  → auto-connect
network ethernet                    → ethernet status
network ethernet info               → ethernet details
network ip                          → all IP addresses
network ip4                         → IPv4 only
network ip6                         → IPv6 only
network gateway                     → default gateway
network public-ip                   → public IP
network hostname                    → hostname
network hostname "thinkpad"         → set hostname
network dns                         → DNS servers
network dns set 1.1.1.1 8.8.8.8    → set DNS
network dns set --auto              → use DHCP DNS
network dns resolve example.com     → resolve
network dns resolve example.com --type aaaa  → specific type
network dns resolve example.com --type mx    → MX records
network dns reverse 1.1.1.1         → reverse lookup
network dns flush                   → flush cache
network dns cache                   → show cache
network dns cache stats             → cache stats
network dns secure                  → secure DNS status
network dns doh on                  → enable DoH
network dns doh off                 → disable DoH
network dns doh server "https://cloudflare-dns.com/dns-query"  → set DoH server
network dns dot on                  → enable DoT
network dns dot off                 → disable DoT
network dns dot server "1.1.1.1:853"  → set DoT server
network routes                      → routing table
network route add 10.0.0.0/8 192.168.1.1  → add route
network route add 10.0.0.0/8 192.168.1.1 --interface wlan0 --metric 100  → with options
network route remove 10.0.0.0/8    → remove
network route default 192.168.1.1   → set default gateway
network firewall                    → firewall status
network firewall on                 → enable
network firewall off                → disable
network firewall default deny       → default policy
network firewall rules              → list rules
network firewall rule add --direction inbound --action deny --protocol tcp --port 22 --name "block-ssh"  → add rule
network firewall rule add --direction inbound --action allow --protocol tcp --port 443 --name "allow-https"  → allow
network firewall rule add --direction inbound --action deny --protocol tcp --port 22 --rate-limit "10/min" --name "rate-ssh"  → rate limit
network firewall rule add --direction inbound --action deny --port 22 --expires 24h --name "temp"  → temporary
network firewall rule remove <id>   → remove rule
network firewall rule <id>          → rule details
network firewall rule <id> enable   → enable
network firewall rule <id> disable  → disable
network firewall stats              → rule hit stats
network captive-portal              → detect captive portal
network bandwidth                   → current bandwidth
network traffic                     → total traffic
network traffic wlan0               → interface traffic
network connections                 → all connections
network connections where remote-port == 443  → HTTPS
network connections where process == "Firefox"  → by process
network ports                       → listening ports
network port 80                     → who's on port 80
network ping google.com             → ping (4 packets)
network ping google.com --count 10  → 10 packets
network traceroute google.com       → traceroute
network whois example.com           → whois
network speed                       → speed test
network proxy                       → proxy status
network proxy on                    → enable
network proxy off                   → disable
network proxy set http proxy.local 3128  → set proxy
network proxy bypass "localhost,127.0.0.1"  → bypass list
watch network                       → stream events
watch network bandwidth             → stream bandwidth
watch network wifi                  → stream WiFi events
watch network connections           → stream connections


# ── BLUETOOTH ─────────────────────────────────────────────────────────

bluetooth
#   📶 Bluetooth
#   ├─ State     On
#   ├─ Address   AA:BB:CC:DD:EE:FF
#   ├─ Name      thinkpad
#   ├─ Paired    3 devices
#   ├─ Connected 2 devices
#   └─ Discoverable Yes

bluetooth info                      → full details
bluetooth on                        → enable
bluetooth off                       → disable
bluetooth scan                      → scan (10s)
bluetooth scan --duration 30s       → scan 30s
bluetooth devices                   → all known devices
bluetooth devices where paired      → paired
bluetooth devices where connected   → connected
bluetooth devices where type == ble → BLE only
bluetooth device <id>               → device summary
bluetooth device <id> info          → full details
bluetooth pair <id>                 → pair
bluetooth pair <id> --pin "0000"    → with PIN
bluetooth unpair <id>               → unpair
bluetooth connect <id>              → connect
bluetooth disconnect <id>           → disconnect
bluetooth disconnect-all            → disconnect all
bluetooth device <id> trust         → trust
bluetooth device <id> untrust       → untrust
bluetooth device <id> block         → block
bluetooth device <id> unblock       → unblock
bluetooth device <id> alias "My Headphones"  → set alias
bluetooth device <id> alias --clear → clear alias
bluetooth device <id> auto-connect on  → enable auto-connect
bluetooth device <id> auto-connect off → disable
bluetooth device <id> profiles      → list profiles
bluetooth device <id> gatt          → GATT services
bluetooth device <id> gatt <svc> read <char>  → read characteristic
bluetooth device <id> gatt <svc> write <char> "data"  → write
bluetooth device <id> gatt <svc> subscribe <char>  → subscribe
bluetooth advertise start --name "MyDevice" --services "uuid1"  → start BLE advertise
bluetooth advertise stop            → stop
bluetooth audio                     → audio devices
bluetooth audio <id>                → audio details
bluetooth audio <id> activate       → set active audio
bluetooth audio <id> codec aac      → set codec
bluetooth name                      → BT name
bluetooth name "My Laptop"          → set name
bluetooth discoverable on           → make discoverable
bluetooth discoverable off          → hide
watch bluetooth                     → stream events
watch bluetooth battery             → battery changes


# ── DNS ───────────────────────────────────────────────────────────────

dns info                            → full DNS config
dns servers                         → DNS servers
dns set 1.1.1.1 8.8.8.8            → set servers
dns resolve example.com             → resolve
dns resolve example.com --type aaaa → specific type
dns reverse 1.1.1.1                 → reverse
dns cache                           → show cache
dns cache flush                     → flush
dns cache stats                     → stats
dns secure                          → secure DNS status
dns doh on                          → enable DoH
dns doh server "https://..."        → set DoH server
dns dot on                          → enable DoT
dns custom                          → custom records
dns custom add my.local 192.168.1.5 → add record
dns custom remove my.local          → remove
dns stats                           → query stats
dns stats top-domains               → most queried
dns benchmark                       → benchmark servers
dns benchmark --servers "1.1.1.1,8.8.8.8"  → specific servers
watch dns                           → stream DNS events


# ── TUNNELS ───────────────────────────────────────────────────────────

tunnels                             → list all tunnels
tunnels where state == connected    → connected
tunnels where type == wireguard     → WireGuard
tunnel <id>                         → tunnel summary
tunnel <id> info                    → full details
tunnel create --name "work-vpn" --type wireguard --endpoint "vpn.work.com:51820" --private-key <key> --allowed-ips "10.0.0.0/8" --address "10.0.0.2/32"  → create WireGuard
tunnel create --name "work-vpn" --type wireguard --config ~/work-vpn.conf  → from config file
tunnel create --name "office" --type openvpn --config ~/office.ovpn  → create OpenVPN
tunnel create --name "dev" --type ssh --endpoint "dev.example.com" --user "admin" --key ~/.ssh/id --local-port 8080 --remote-port 80  → SSH tunnel
tunnel create --name "full" --type wireguard --endpoint "vpn.work.com:51820" --private-key <key> --allowed-ips "0.0.0.0/0" --dns "10.0.0.1" --kill-switch --auto-connect --keepalive 25  → all options
tunnel connect <id>                 → connect
tunnel connect <id> --timeout 30    → with timeout
tunnel disconnect <id>              → disconnect
tunnel destroy <id>                 → destroy
tunnel destroy <id> --force         → force destroy
tunnel <id> set endpoint "new-vpn.com:51820"  → change endpoint
tunnel <id> set kill-switch on      → enable kill switch
tunnel <id> set auto-connect on     → enable auto-connect
tunnel <id> set dns "10.0.0.1"      → set DNS
tunnel <id> set keepalive 25        → set keepalive
tunnel <id> export ~/tunnel.conf    → export config
tunnel import ~/tunnel.conf --name "imported"  → import
tunnel presets                      → list presets
tunnel preset <id>                  → connect to preset
watch tunnels                       → stream tunnel events


# ── DISCOVERY ─────────────────────────────────────────────────────────

discovery                           → list discovered services
discovery scan                      → scan all protocols (10s)
discovery scan --protocol mdns      → mDNS only
discovery scan --protocol ssdp      → SSDP only
discovery scan --duration 30s       → scan 30s
discovery mdns                      → mDNS services
discovery ssdp                      → SSDP services
discovery advertise --name "MyService" --type "_http._tcp" --port 8080  → advertise
discovery advertise status          → advertised services
discovery advertise stop <id>       → stop advertising
discovery peers                     → smart-protocol peers
discovery peers scan                → scan for peers
watch discovery                     → stream events


# ── WEBSOCKETS ────────────────────────────────────────────────────────

web get "https://api.example.com/data"  → HTTP GET
web get "https://api.example.com/data" --header "Authorization: Bearer token"  → with header
web get "https://api.example.com/data" --query "page=1&limit=10"  → with query
web post "https://api.example.com" '{"key":"value"}'  → HTTP POST
web put "https://api.example.com/1" '{"key":"new"}'  → HTTP PUT
web patch "https://api.example.com/1" '{"key":"patched"}'  → PATCH
web delete "https://api.example.com/1"  → DELETE
web download "https://file.zip" ~/file.zip  → download
web download "https://file.zip" ~/file.zip --progress  → with progress
web download "https://large.iso" ~/large.iso --resume  → resume
web ws "ws://localhost:8080"        → WebSocket
web ws list                         → active connections
web ws send <id> "message"          → send
web ws close <id>                   → close


# ── SOCKETS ───────────────────────────────────────────────────────────

socket info                         → statistics
socket list                         → all sockets
socket list where state == listen   → listening
socket list where protocol == tcp   → TCP
socket list where port == 80        → port 80