#/bin/bash

iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F

iptables -X
iptables -t nat -X
iptables -t mangle -X
iptables -t raw -X