#!/bin/bash

# Run prerequisite commands for both server types (only if installing)
run_prerequisites() {
    echo "Running prerequisite commands..."
    ARCH=$(uname -m); OS=$(uname -s | tr '[:upper:]' '[:lower:]'); \
    [ "$ARCH" = "x86_64" ] && ARCH="amd64" || ARCH="arm64"; \
    FILE_NAME="backhaul_${OS}_${ARCH}.tar.gz"; \
    echo "Downloading $FILE_NAME..."; \
    curl -L -O "https://github.com/Musixal/Backhaul/releases/latest/download/$FILE_NAME"; \
    mkdir -p /root/backhaul && tar -xzf "$FILE_NAME" -C /root/backhaul && \
    { rm -f "$FILE_NAME" /root/backhaul/LICENSE /root/backhaul/README.md; echo "Extraction successful, cleaned up files."; } || \
    { echo "Extraction failed!"; exit 1; }

    # Check if prerequisite commands were successful
    if [ $? -ne 0 ]; then
        echo "Prerequisite commands failed. Exiting..."
        exit 1
    fi
}

# Function to create and activate systemd service
create_systemd_service() {
    echo "Creating systemd service file for backhaul..."
    cat > /etc/systemd/system/backhaul.service << EOF
[Unit]
Description=Backhaul Reverse Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=/root/backhaul/backhaul -c /root/backhaul/config.toml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    # Verify service file creation
    if [ -f /etc/systemd/system/backhaul.service ]; then
        echo "Systemd service file created successfully at /etc/systemd/system/backhaul.service"
    else
        echo "Failed to create systemd service file. Exiting..."
        exit 1
    fi

    # Activate the service
    echo "Activating backhaul service..."
    sudo systemctl daemon-reload
    sudo systemctl enable backhaul.service
    sudo systemctl start backhaul.service

    # Check if service started successfully
    if systemctl is-active --quiet backhaul.service; then
        echo "Backhaul service started successfully."
    else
        echo "Failed to start backhaul service. Please check 'systemctl status backhaul.service' for details."
        exit 1
    fi
}

# Function to enable BBR
enable_bbr() {
    echo "Enabling BBR congestion control..."

    # Check if BBR is available in the kernel
    if ! sysctl net.ipv4.tcp_available_congestion_control | grep -q "bbr"; then
        echo "BBR is not supported by this kernel. Please ensure your kernel version is 4.9 or higher. Exiting..."
        exit 1
    fi

    # Set BBR as the congestion control algorithm and fq as the queue discipline
    echo "Configuring sysctl for BBR..."
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
    fi
    if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
    fi

    # Apply sysctl changes
    echo "Applying sysctl changes..."
    sudo sysctl -p >/dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to apply sysctl changes. Exiting..."
        exit 1
    fi

    # Verify BBR is enabled
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo "BBR has been successfully enabled."
    else
        echo "Failed to enable BBR. Please check your system configuration."
        exit 1
    fi
}

# Prompt user for server selection
echo "Which server are you on?"
echo "1) IRAN Server"
echo "2) KHAREJ Server"
echo "3) Remove Tunnel"
echo "4) Enable BBR"
read -p "Enter your choice (1, 2, 3, or 4): " choice

case $choice in
    1)
        run_prerequisites
        echo "Executing commands for IRAN Server..."
        # Prompt for token
        read -p "Enter the token: " token
        if [ -z "$token" ]; then
            echo "Token cannot be empty. Exiting..."
            exit 1
        fi

        # Prompt for number of ports
        read -p "How many ports do you want to tunnel? " num_ports
        # Validate number of ports (must be a positive integer)
        if ! [[ "$num_ports" =~ ^[0-9]+$ ]] || [ "$num_ports" -lt 1 ]; then
            echo "Invalid number of ports. Must be a positive integer. Exiting..."
            exit 1
        fi

        # Collect port numbers
        ports=()
        for ((i=1; i<=num_ports; i++)); do
            read -p "Enter port $i: " port
            # Validate port (must be a number between 1 and 65535)
            if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                echo "Invalid port. Must be a number between 1 and 65535. Exiting..."
                exit 1
            fi
            ports+=("$port")
        done

        # Format ports for TOML (comma-separated, quoted)
        ports_toml=$(printf '"%s",' "${ports[@]}" | sed 's/,$//')

        # Create config.toml with
