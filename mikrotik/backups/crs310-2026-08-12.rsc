# 2026-08-12 00:26:51 by RouterOS 7.23.3
# software id = CEXT-F918
#
# model = CRS310-8G+2S+
# serial number = HGH09K4PD6K
/interface bridge
add name=bridge vlan-filtering=yes
/interface ethernet
set [ find default-name=ether1 ] comment=TRUNK
set [ find default-name=ether2 ] comment=NAS
set [ find default-name=ether3 ] comment=MS-01
set [ find default-name=ether4 ] comment=CCTV
set [ find default-name=ether5 ] comment=TV
set [ find default-name=ether6 ] comment="NAS 2.5"
/interface vlan
add interface=bridge name=CCTV vlan-id=20
add interface=bridge name=Management vlan-id=10
add interface=bridge name=NAS vlan-id=40
add interface=bridge name=Servers vlan-id=30
/interface list
add name=WAN
add name=LAN
/ip pool
add name=dhcp_pool_cctv ranges=10.10.20.2-10.10.20.254
add name=dhcp_pool_servers ranges=10.10.30.2-10.10.30.254
add name=dhcp_pool_nas ranges=10.10.40.2-10.10.40.254
/ip dhcp-server
add address-pool=dhcp_pool_cctv interface=CCTV name=dhcp-cctv
add address-pool=dhcp_pool_servers interface=Servers name=dhcp-servers
add address-pool=dhcp_pool_nas interface=NAS name=dhcp-nas
/interface bridge port
add bridge=bridge interface=ether1
add bridge=bridge interface=ether2 pvid=40
add bridge=bridge interface=ether3 pvid=30
add bridge=bridge interface=ether4 pvid=20
add bridge=bridge interface=ether5 pvid=30
add bridge=bridge interface=ether6 pvid=40
add bridge=bridge interface=ether7 pvid=10
add bridge=bridge interface=ether8
add bridge=bridge interface=sfp-sfpplus1
add bridge=bridge interface=sfp-sfpplus2
/interface bridge vlan
add bridge=bridge tagged=ether1,bridge vlan-ids=10
add bridge=bridge tagged=ether1 untagged=ether4 vlan-ids=20
add bridge=bridge tagged=ether1 untagged=ether3,ether5 vlan-ids=30
add bridge=bridge tagged=ether1 untagged=ether2 vlan-ids=40
add bridge=bridge tagged=ether1 vlan-ids=60
/interface ethernet switch
set switch1 l3-hw-offloading=yes
/interface list member
add interface=ether1 list=WAN
add interface=ether2 list=LAN
add interface=ether3 list=LAN
add interface=ether4 list=LAN
add interface=ether5 list=LAN
add interface=ether6 list=LAN
add interface=ether7 list=LAN
add interface=ether8 list=LAN
add interface=sfp-sfpplus1 list=LAN
add interface=sfp-sfpplus2 list=LAN
/ip address
add address=10.10.10.2/24 interface=Management network=10.10.10.0
add address=10.10.20.1/24 interface=CCTV network=10.10.20.0
add address=10.10.30.1/24 interface=Servers network=10.10.30.0
add address=10.10.40.1/24 interface=NAS network=10.10.40.0
/ip dhcp-client
# DHCP client can not run on slave or passthrough interface!
add interface=ether1 name=client1
/ip dhcp-server lease
add address=10.10.20.2 mac-address=50:E5:38:93:57:67 server=dhcp-cctv
add address=10.10.20.3 mac-address=0C:75:D2:84:34:37 server=dhcp-cctv
add address=10.10.20.4 mac-address=0C:75:D2:84:34:3A server=dhcp-cctv
add address=10.10.40.2 comment="TK-NAS 2.5GbE (USB adapter)" mac-address=\
    00:E0:4C:68:00:67 server=dhcp-nas
add address=10.10.30.252 comment=erp-apps mac-address=BC:24:11:27:32:53 \
    server=dhcp-servers
add address=10.10.30.251 comment=mariadb mac-address=BC:24:11:29:5D:53 \
    server=dhcp-servers
add address=10.10.30.250 comment=erp mac-address=BC:24:11:37:5C:47 server=\
    dhcp-servers
add address=10.10.30.248 comment=homeassistant mac-address=BC:24:11:62:74:43 \
    server=dhcp-servers
add address=10.10.30.244 comment=cloudflared mac-address=BC:24:11:B9:47:4D \
    server=dhcp-servers
add address=10.10.30.240 comment=sure mac-address=BC:24:11:87:6B:91 server=\
    dhcp-servers
add address=10.10.30.238 comment=ollama mac-address=BC:24:11:A9:8B:14 server=\
    dhcp-servers
add address=10.10.30.237 comment=nginxproxymanager mac-address=\
    BC:24:11:87:F3:B7 server=dhcp-servers
add address=10.10.30.236 comment=zitadel mac-address=BC:24:11:A3:5C:23 \
    server=dhcp-servers
add address=10.10.30.235 comment=frigate mac-address=BC:24:11:A5:E0:5E \
    server=dhcp-servers
add address=10.10.30.234 comment=proxmox mac-address=58:47:CA:7C:08:4D \
    server=dhcp-servers
add address=10.10.30.232 comment=hackintoshsiPro mac-address=\
    BC:24:11:11:93:2E server=dhcp-servers
add address=10.10.30.230 comment=termix mac-address=BC:24:11:28:C8:E7 server=\
    dhcp-servers
add address=10.10.30.228 comment=proxmox-backup-server mac-address=\
    BC:24:11:D5:3A:94 server=dhcp-servers
add address=10.10.40.3 comment="TK-NAS 1GbE (onboard)" mac-address=\
    90:09:D0:51:C2:AD server=dhcp-nas
/ip dhcp-server network
add address=10.10.20.0/24 dns-server=10.10.10.1 gateway=10.10.20.1
add address=10.10.30.0/24 dns-server=10.10.10.1 gateway=10.10.30.1
add address=10.10.40.0/24 dns-server=10.10.10.1 gateway=10.10.40.1
/ip dns
set servers=10.10.0.1,8.8.8.8
/ip route
add disabled=no distance=1 dst-address=0.0.0.0/0 gateway=10.10.0.1 \
    routing-table=main scope=30 suppress-hw-offload=no target-scope=10
/system clock
set time-zone-name=Africa/Dar_es_Salaam
/system health settings
set fan-min-speed-percent=0% fan-target-temp=62C
