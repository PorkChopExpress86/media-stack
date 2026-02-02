#!/bin/bash

# Fix HomeKit Firewall Rules
# This script opens the necessary ports for Home Assistant HomeKit Bridge and mDNS.

echo "Checking UFW status..."
if sudo ufw status | grep -q "Status: active"; then
    echo "UFW is active. Applying rules..."
else
    echo "UFW is not active, but adding rules anyway in case it is enabled later..."
fi

# Allow HomeKit Bridge port (defined in HA config)
echo "Allowing TCP port 21064 (HomeKit Bridge)..."
sudo ufw allow 21064/tcp comment 'Home Assistant HomeKit Bridge'

# Allow mDNS (Multicast DNS) for device discovery
echo "Allowing UDP port 5353 (mDNS/Zeroconf)..."
sudo ufw allow 5353/udp comment 'mDNS Zeroconf'

# Reload UFW to apply changes
echo "Reloading UFW..."
sudo ufw reload

echo "Firewall rules updated. You may need to restart Home Assistant for mDNS to re-broadcast."
