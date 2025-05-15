#!/bin/bash

# Configuration
WHOIS_SERVER="whois.apnic.net"

# Prompt user for ASN number
read -p "Enter ASN number: " asn_number

# Fetch **ONLY** IPv4 prefixes
echo "Querying ${WHOIS_SERVER} for IPv4 prefixes originated by AS${asn_number}..."
prefixes=$(whois -h "$WHOIS_SERVER" -i origin "AS${asn_number}" | grep '^route:' | awk '{print $2}')

# Check if prefixes were found
if [ -z "$prefixes" ]; then
    echo "Error: No IPv4 prefixes found for AS${asn_number}."
    exit 1
fi

# Process deduplication using `aggregate`
if command -v aggregate &>/dev/null; then
    summarized_prefixes=$(echo "$prefixes" | sort -V | aggregate)
else
    echo "Error: aggregate command not found. Install bgpq3 to use it."
    exit 1
fi

# Function to generate reverse DNS zone configuration
generate_zone_config() {
    ip="$1"
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
    reversed_ip="$o3.$o2.$o1"
    echo "zone \"$reversed_ip.in-addr.arpa\" {"
    echo "    type master;"
    echo "    file \"/var/cache/bind/$reversed_ip.in-addr.arpa\";"
    echo "};"
}

# Generate zone configuration from summarized prefixes
zone_config=""
while read -r prefix; do
    IFS='/' read -r base_ip mask <<< "$prefix"

    IFS='.' read -r a b c d <<< "$base_ip"

    # Calculate /24 subnets
    subnets=$((1 << (24-mask)))
    for i in $(seq 0 $((subnets-1)) ); do
        subnet="$a.$b.$((c + i)).0"
        zone_config+=$(generate_zone_config "$subnet")$'\n'
    done
done <<< "$summarized_prefixes"

# Ask user where to output the zone config
read -p "Do you want to display the zone config on the terminal? (y/n): " display_choice

if [[ "$display_choice" == "y" ]]; then
    echo "$zone_config"
    exit 0
fi

read -p "Enter the file path to save the zone config: " file_path

# Check if the file already exists or the path is not accessible
if [[ -e "$file_path" ]]; then
    echo "Error: File already exists at $file_path."
    exit 1
elif [[ ! -w "$(dirname "$file_path")" ]]; then
    echo "Error: Directory is not writable."
    exit 1
fi

# Write zone config to file
echo "$zone_config" > "$file_path"
echo "Zone config successfully written to $file_path."
exit 0
