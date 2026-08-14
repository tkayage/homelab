# 2026-08-12 00:26:50 by RouterOS 7.23.3
# software id = 9KJ1-3SIT
#
# model = C53UiG+5HPaxD2HPaxD
# serial number = HF7090JSGWQ
/interface bridge
add name=bridge vlan-filtering=yes
/interface ethernet
set [ find default-name=ether1 ] comment=CRS-SWITCH
set [ find default-name=ether4 ] comment=YAS-INTERNET
set [ find default-name=ether5 ] comment=DATAFLOW-INTERNET
/interface wifi
set [ find default-name=wifi2 ] channel.band=2ghz-n configuration.mode=ap \
    .ssid=Apollo disabled=no name=Apollo security.authentication-types=\
    wpa2-psk,wpa3-psk
set [ find default-name=wifi1 ] channel.band=5ghz-ax configuration.mode=ap \
    .ssid=Skynet disabled=no name=Skynet security.authentication-types=\
    wpa2-psk,wpa3-psk
/interface wireguard
add comment=back-to-home-vpn listen-port=48808 mtu=1420 name=back-to-home-vpn
add listen-port=4042 mtu=1420 name=wg-aws
/interface vlan
add interface=bridge name="Apollo Guests" vlan-id=60
add interface=bridge name=CCTV vlan-id=20
add interface=bridge name=Management vlan-id=10
add interface=bridge name=NAS vlan-id=40
add interface=bridge name=Servers vlan-id=30
add interface=bridge name=lan vlan-id=50
/interface list
add name=WAN
add name=LAN
add name=VPN_ONLY
/iot wiliot servers
set *1 address=mqtt.us-east-2.prod.wiliot.cloud name="Wiliot US East"
/ip pool
add name=dhcp_pool3 ranges=10.10.0.10-10.10.0.254
add name=dhcp_pool4 ranges=10.10.10.2-10.10.10.254
add name=dhcp_pool5 ranges=10.10.60.2-10.10.60.254
add name=dhcp_pool14 ranges=10.10.50.2-10.10.50.100
/ip dhcp-server
add address-pool=dhcp_pool3 interface=bridge lease-time=8h30m name=dhcp1
add address-pool=dhcp_pool4 interface=Management name=dhcp2
add address-pool=dhcp_pool5 interface="Apollo Guests" name=dhcp3
add address-pool=dhcp_pool14 interface=lan name=dhcp7
/routing table
add fib name=skynet-via-aws
add fib name=wg-aws-route
add fib name=to-yas
add fib name=to-dataflow
/user group
add comment=minimal name=minimal policy="ssh,read,test,winbox,!local,!telnet,!\
    ftp,!reboot,!write,!policy,!password,!web,!sniff,!sensitive,!api,!romon,!r\
    est-api"
/app
set cinny firewall-redirects=8094:80:tcp:web
set goaway container-command-lines=goaway:none:docker.io/pommee/goaway:latest
set home-assistant container-command-lines=\
    home-assistant:none:lscr.io/linuxserver/homeassistant
set n8n firewall-redirects=5678:5678:tcp:web
set nextcloud container-command-lines="db:none:docker.io/postgres:17,redis:non\
    e:docker.io/valkey/valkey:/bin/sh -c 'valkey-server --port 6379 --appendon\
    ly yes --requirepass \$VALKEY_PASSWORD',server:none:docker.io/nextcloud:ap\
    ache"
set pihole environment="pihole:FTLCONF_dns_listeningMode=all,pihole:FTLCONF_we\
    bserver_api_password=<REDACTED-see-router-directly>"
set redlib firewall-redirects=8087:8080:tcp:web
set solr container-command-lines=solr:none:docker.io/solr:latest
set uptime-kuma container-command-lines=\
    uptime-kuma:none:docker.io/louislam/uptime-kuma:1
/interface bridge port
add bridge=bridge interface=ether1
add bridge=bridge interface=ether2
add bridge=bridge interface=ether3 pvid=10
add bridge=bridge interface=Skynet pvid=50
add bridge=bridge interface=Apollo pvid=60
/interface bridge vlan
add bridge=bridge tagged=ether1,bridge untagged=ether2 vlan-ids=10
add bridge=bridge tagged=ether1,bridge vlan-ids=20
add bridge=bridge tagged=ether1,bridge vlan-ids=30
add bridge=bridge tagged=ether1,bridge vlan-ids=40
add bridge=bridge tagged=ether1,bridge untagged=Skynet vlan-ids=50
add bridge=bridge tagged=ether1,bridge untagged=Apollo vlan-ids=60
/interface detect-internet
set detect-interface-list=all
/interface list member
add interface=ether4 list=WAN
add interface=Management list=LAN
add interface=bridge list=LAN
add interface=ether5 list=WAN
add interface=Skynet list=LAN
add interface=Apollo list=LAN
add interface=NAS list=LAN
/interface wireguard peers
add allowed-address=0.0.0.0/0 comment="AWS CHR VPN hub" endpoint-address=\
    router.hapa.dev endpoint-port=4041 interface=wg-aws name=peer5 \
    persistent-keepalive=25s public-key=\
    "Nwp6qBCjGU+d2fZzGL62lOuQJxFjANg5V6jbh+l5bCg="
/ip address
add address=10.10.0.1/24 interface=bridge network=10.10.0.0
add address=10.10.50.1/24 interface=lan network=10.10.50.0
add address=10.10.60.1/24 interface="Apollo Guests" network=10.10.60.0
add address=10.10.10.1/24 interface=Management network=10.10.10.0
add address=10.0.1.2/30 comment="WireGuard tunnel address" interface=wg-aws \
    network=10.0.1.0
/ip arp
add address=10.10.30.30 interface=Servers mac-address=58:47:CA:7C:08:4D
/ip cloud
set back-to-home-vpn=enabled ddns-enabled=yes ddns-update-interval=10m
/ip cloud back-to-home-user
add allow-lan=yes comment="hAP ax^3" name=TK-PIXEL public-key=\
    "kkNgcRmaDcQIZK2NV6Vb4cXWjmkTtuhz6JFQMtX5pWY="
/ip dhcp-client
add add-default-route=no interface=ether5 name=client1
add add-default-route=no interface=ether4 name=client2
/ip dhcp-server lease
add address=10.10.40.2 client-id=1:90:9:d0:51:c2:ad mac-address=\
    90:09:D0:51:C2:AD server=*7
add address=10.10.20.2 client-id=1:50:e5:38:93:57:67 mac-address=\
    50:E5:38:93:57:67 server=*6
add address=10.10.20.3 client-id=1:c:75:d2:84:34:37 mac-address=\
    0C:75:D2:84:34:37 server=*6
add address=10.10.20.4 client-id=1:c:75:d2:84:34:3a mac-address=\
    0C:75:D2:84:34:3A server=*6
add address=10.10.30.252 client-id=\
    ff:ca:53:9:5a:0:2:0:0:ab:11:8b:8f:e6:82:d:97:ea:cb mac-address=\
    BC:24:11:27:32:53 server=*8
add address=10.10.30.251 client-id=\
    ff:ca:53:9:5a:0:2:0:0:ab:11:54:fb:8b:23:79:af:88:4 mac-address=\
    BC:24:11:29:5D:53 server=*8
add address=10.10.30.250 client-id=\
    ff:ca:53:9:5a:0:2:0:0:ab:11:cd:10:3a:eb:c7:c7:3b:7f mac-address=\
    BC:24:11:37:5C:47 server=*8
add address=10.10.30.248 mac-address=BC:24:11:62:74:43 server=*8
add address=10.10.30.244 client-id=\
    ff:c1:cc:e6:6c:0:2:0:0:ab:11:97:86:71:63:d0:da:de:b4 mac-address=\
    BC:24:11:B9:47:4D server=*8
add address=10.10.50.100 client-id=1:a4:30:7a:10:f1:ed mac-address=\
    A4:30:7A:10:F1:ED server=dhcp7
add address=10.10.30.240 mac-address=BC:24:11:87:6B:91 server=*8
add address=10.10.30.238 client-id=\
    ff:8e:a0:ee:c4:0:2:0:0:ab:11:6d:93:a4:99:da:eb:c7:8 mac-address=\
    BC:24:11:A9:8B:14 server=*8
add address=10.10.30.237 client-id=\
    ff:11:87:f3:b7:0:1:0:1:31:ce:eb:e4:bc:24:11:87:f3:b7 mac-address=\
    BC:24:11:87:F3:B7 server=*8
add address=10.10.30.236 mac-address=BC:24:11:A3:5C:23 server=*8
add address=10.10.30.235 client-id=\
    ff:11:a5:e0:5e:0:1:0:1:31:d1:44:82:bc:24:11:a5:e0:5e mac-address=\
    BC:24:11:A5:E0:5E server=*8
add address=10.10.30.234 client-id=1:58:47:ca:7c:8:4d mac-address=\
    58:47:CA:7C:08:4D server=*8
/ip dhcp-server network
add address=10.10.0.0/24 dns-server=10.10.0.1,8.8.8.8 gateway=10.10.0.1
add address=10.10.10.0/24 dns-server=10.10.10.1 gateway=10.10.10.1
add address=10.10.20.0/24 dns-server=10.10.20.1 gateway=10.10.20.1
add address=10.10.30.0/24 dns-server=10.10.30.1 gateway=10.10.30.1
add address=10.10.40.0/24 dns-server=10.10.40.1 gateway=10.10.40.1
add address=10.10.50.0/24 dns-server=10.10.50.1 gateway=10.10.50.1
add address=10.10.60.0/24 dns-server=10.10.60.1 gateway=10.10.60.1
add address=192.168.1.0/24 dns-server=192.168.1.1 gateway=192.168.1.1
/ip dns
set address-list-extra-time=1d allow-remote-requests=yes servers=\
    8.8.8.8,10.10.0.1
/ip dns static
add address=10.10.30.237 name=nas.kayage.co type=A
add address=10.10.30.237 name=jumba.kayage.co type=A
add address=10.10.30.237 name=cctv.kayage.co type=A
add address=10.10.30.237 name=router.kayage.co type=A
add address=10.10.30.237 name=sure.kayage.co type=A
add address=10.10.30.237 name=code.hapa.dev type=A
add address=10.10.30.237 name=proxy.kayage.co type=A
add address=10.10.30.237 name=ha.kayage.co type=A
add address=10.10.30.237 name=proxmox.kayage.go type=A
add address=10.10.30.237 name=home.kayage.co type=A
add address=10.10.30.250 name=erp.kayage.co type=A
add address=10.10.30.251 name=mariadb.kayage.co type=A
add address=10.10.30.250 name=traefik.kayage.co type=A
add address=10.10.30.250 name=pakacha.kayage.co type=A
add address=10.10.30.250 name=msonge.kayage.co type=A
add address=10.10.30.250 name=afifis.kayage.co type=A
add address=10.10.30.237 name=zitadel.kayage.co type=A
add address=10.10.30.237 name=t3code.hapa.dev type=A
add address=10.10.30.237 name=t3code.kayage.co type=A
add address=10.10.30.237 comment=homelab-platform-local-edge regexp=\
    "^.+\\.app\\.kayage\\.co\$" ttl=5m type=A
add address=10.10.30.237 name=code.kayage.co type=A
add address=10.10.30.237 name=server.hapa.dev type=A
add address=10.10.30.237 name=5g.kayage.co type=A
add address=10.10.30.237 name=openhands.kayage.co type=A
/ip firewall address-list
add address=10.0.0.0/8 comment="Private: RFC1918" list=skynet-local
add address=172.16.0.0/12 comment="Private: RFC1918" list=skynet-local
add address=192.168.0.0/16 comment="Private: RFC1918" list=skynet-local
add address=13.247.209.167 comment=\
    "AWS CHR WireGuard endpoint (router.hapa.dev)" list=wg-aws-endpoint
add address=paypoint.selcommobile.com comment=\
    "Selcom PayPoint (auto-resolved)" list=selcom-paypoint
add address=apigw.selcommobile.com comment="Selcom API GW (auto-resolved)" \
    list=selcom-paypoint
add address=10.10.60.0/24 comment="Apollo WiFi" list=wifi-src
/ip firewall filter
add action=passthrough chain=forward disabled=yes
add action=drop chain=forward disabled=yes in-interface="Apollo Guests" \
    out-interface=ether4
add action=accept chain=input comment=WG dst-port=4042 protocol=udp
add action=accept chain=input dst-port=123 protocol=udp src-address-list=\
    10.10.20.1/24
add action=drop chain=forward comment="Block internet traffic from cameras" \
    out-interface-list=WAN src-address=10.10.20.0/24
/ip firewall mangle
add action=change-mss chain=forward comment="MSS clamp outbound to AWS" \
    new-mss=1380 out-interface=wg-aws protocol=tcp tcp-flags=syn
add action=change-mss chain=forward comment="MSS clamp inbound from AWS" \
    in-interface=wg-aws new-mss=1380 protocol=tcp tcp-flags=syn
add action=mark-routing chain=output comment=\
    "Route WG-AWS tunnel packets via Microwave (ether5)" dst-address-list=\
    wg-aws-endpoint dst-port=4041 new-routing-mark=wg-aws-route protocol=udp
add action=accept chain=prerouting comment=\
    "Bypass WAN split: internal/VPN destinations" dst-address-list=\
    skynet-local
add action=accept chain=prerouting comment=\
    "Bypass WAN split: Selcom API/PayPoint via WG" dst-address-list=\
    selcom-paypoint
add action=mark-routing chain=prerouting comment=\
    "Apollo WiFi -> ether4 (YAS)" new-routing-mark=to-yas passthrough=no \
    src-address-list=wifi-src
add action=mark-routing chain=prerouting comment=\
    "Skynet WiFi + all wired -> ether5 (DATAFLOW)" new-routing-mark=\
    to-dataflow passthrough=no
/ip firewall nat
add action=masquerade chain=srcnat out-interface=ether5
add action=masquerade chain=srcnat log=yes out-interface=ether4
/ip route
add disabled=no distance=1 dst-address=172.31.0.0/20 gateway="" \
    routing-table=main scope=30 target-scope=10
add comment="Route to AWS VPC via WireGuard" dst-address=172.31.0.0/16 \
    gateway=wg-aws
add comment="Skynet internet via AWS CHR (WireGuard)" disabled=yes distance=1 \
    dst-address=0.0.0.0/0 gateway=10.0.1.1 routing-table=skynet-via-aws \
    scope=30 target-scope=10
add check-gateway=ping comment="WG-AWS failover via YAS/5G (ether4)" \
    disabled=no distance=2 dst-address=0.0.0.0/0 gateway=192.168.188.1 \
    routing-table=wg-aws-route scope=30 target-scope=10
add check-gateway=ping comment="WG-AWS primary via DATAFLOW (ether5)" \
    disabled=no distance=1 dst-address=0.0.0.0/0 gateway=192.168.1.1 \
    routing-table=wg-aws-route scope=30 target-scope=10
add comment="Selcom PayPoint via AWS WG tunnel" dst-address=102.222.27.21/32 \
    gateway=10.0.1.1
add comment="Selcom API GW via AWS WG tunnel" dst-address=102.222.27.17/32 \
    gateway=10.0.1.1
add check-gateway=ping comment="Main default: YAS (ether4)" distance=1 \
    dst-address=0.0.0.0/0 gateway=192.168.188.1
add check-gateway=ping comment="Main failover: DATAFLOW (ether5)" distance=2 \
    dst-address=0.0.0.0/0 gateway=192.168.1.1
add check-gateway=ping comment="Apollo primary: YAS (ether4)" distance=1 \
    dst-address=0.0.0.0/0 gateway=192.168.188.1 routing-table=to-yas
add check-gateway=ping comment="Apollo failover: DATAFLOW (ether5)" distance=\
    2 dst-address=0.0.0.0/0 gateway=192.168.1.1 routing-table=to-yas
add check-gateway=ping comment="Skynet+wired primary: DATAFLOW (ether5)" \
    distance=1 dst-address=0.0.0.0/0 gateway=192.168.1.1 routing-table=\
    to-dataflow
add check-gateway=ping comment="Skynet+wired failover: YAS (ether4)" \
    distance=2 dst-address=0.0.0.0/0 gateway=192.168.188.1 routing-table=\
    to-dataflow
add comment="CCTV via CRS310 L3 offload" dst-address=10.10.20.0/24 gateway=\
    10.10.10.2
add comment="Servers via CRS310 L3 offload" dst-address=10.10.30.0/24 \
    gateway=10.10.10.2
add comment="NAS via CRS310 L3 offload" dst-address=10.10.40.0/24 gateway=\
    10.10.10.2
/ip traffic-flow
set enabled=yes interfaces=ether4,ether5,Servers
/system clock
set time-zone-name=Africa/Dar_es_Salaam
/system ntp client
set enabled=yes
/system ntp server
set broadcast=yes enabled=yes manycast=yes multicast=yes
/system ntp client servers
add address=pool.ntp.org
