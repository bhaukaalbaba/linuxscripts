#!/bin/bash

# Prompt user for the zone file path
read -p "Enter the path to the zone file: " zone_file

# Check if the file exists
if [[ ! -f "$zone_file" ]]; then
    echo "Error: Zone file does not exist!"
    exit 1
fi

# Ask user for root domain name
read -p "Enter the root domain name (e.g., ispdns.net): " root_domain

# Define output directory
output_dir="/tmp/var/cache/bind"

# Ensure the output directory exists
mkdir -p "$output_dir"

# Extract and process each zone entry
grep -oP 'zone "\K[^"]+' "$zone_file" | while read -r zone_name; do
    ptr_file="$output_dir/$zone_name"

    # Extract only the first three octets
    zone_ip=$(echo "$zone_name" | sed 's/.in-addr.arpa//')

    # Reverse the octets correctly
    IFS='.' read -r o1 o2 o3 <<< "$zone_ip"
    reversed_prefix="$o3.$o2.$o1"

    # Generate PTR file content
    ptr_content="\$TTL 60\n\n\$ORIGIN $zone_name.\n"
    ptr_content+="@       IN      SOA     rdns1.$root_domain. root.$root_domain.  (\n"
    ptr_content+="                $(date +'%Y%m%d%H') ; Serial\n"
    ptr_content+="                1200      ; Refresh\n"
    ptr_content+="                600       ; Retry\n"
    ptr_content+="                3600      ; Expire\n"
    ptr_content+="                60 )      ; Minimum\n"
    ptr_content+="@                NS     rdns1.$root_domain.\n"
    ptr_content+="@                NS     rdns2.$root_domain.\n"

    # Correctly format `$GENERATE` PTR entries
    ptr_target="$reversed_prefix.\$.rev.$root_domain."
    ptr_content+="\n\$GENERATE 0-255 \$ PTR $ptr_target\n"

    # Write to PTR file
    echo -e "$ptr_content" > "$ptr_file"
    echo "PTR file created: $ptr_file"
done

echo "All PTR files successfully generated in $output_dir."
exit 0
