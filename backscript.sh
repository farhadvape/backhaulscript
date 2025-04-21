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

# Prompt user for server selection
echo "Which server are you on?"
echo "1) IRAN Server"
echo "2) KHAREJ Server"
echo "3) Remove Tunnel"
read -p "Enter your choice (1, 2, or 3): " choice

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

        # Create config.toml with user-provided values
        echo "Creating /root/backhaul/config.toml..."
        cat > /root/backhaul/config.toml << EOF
[server]
bind_addr = "0.0.0.0:5080"
transport = "tcp"
accept_udp = false
token = "${token}"
keepalive_period = 75
nodelay = true
heartbeat = 40
channel_size = 2048
sniffer = false
web_port = 5081
sniffer_log = "/root/backhaul.json"
log_level = "info"
ports = [
    ${ports_toml}
]
EOF

        # Verify file creation
        if [ -f /root/backhaul/config.toml ]; then
            echo "Config file created successfully at /root/backhaul/config.toml"
        else
            echo "Failed to create config file. Exiting..."
            exit 1
        fi

        # Create and activate systemd service
        create_systemd_service
        ;;
    2)
        run_prerequisites
        echo "Executing commands for KHAREJ Server..."
        # Prompt for IRAN IP address
        read -p "Enter the IRAN IP address: " iran_ip
        # Validate IP address format (basic check)
        if [[ ! $iran_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "Invalid IP address format. Exiting..."
            exit 1
        fi

        # Prompt for token
        read -p "Enter the token: " token
        if [ -z "$token" ]; then
            echo "Token cannot be empty. Exiting..."
            exit 1
        fi

        # Create config.toml with user-provided values
        echo "Creating /root/backhaul/config.toml..."
        cat > /root/backhaul/config.toml << EOF
[client]
remote_addr = "${iran_ip}:5080"
transport = "tcp"
token = "${token}"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
sniffer = false
web_port = 5081
sniffer_log = "/root/backhaul.json"
log_level = "info"
EOF

        # Verify file creation
        if [ -f /root/backhaul/config.toml ]; then
            echo "Config file created successfully at /root/backhaul/config.toml"
        else
            echo "Failed to create config file. Exiting..."
            exit 1
        fi

        # Create and activate systemd service
        create_systemd_service
        ;;
    3)
        echo "Removing tunnel configuration..."
        # Disable and stop the backhaul service
        echo "Disabling and stopping backhaul service..."
        sudo systemctl disable backhaul.service 2>/dev/null
        sudo systemctl stop backhaul.service 2>/dev/null

        # Remove the systemd service file
        echo "Removing systemd service file..."
        if [ -f /etc/systemd/system/backhaul.service ]; then
            sudo rm -f /etc/systemd/system/backhaul.service
            if [ $? -eq 0 ]; then
                echo "Systemd service file removed successfully."
            else
                echo "Failed to remove systemd service file. Exiting..."
                exit 1
            fi
        else
            echo "Systemd service file does not exist. Skipping removal."
        fi

        # Reload systemd to reflect changes
        echo "Reloading systemd daemon..."
        sudo systemctl daemon-reload

        # Remove backhaul directory and backhaul.json
        echo "Removing /root/backhaul directory and /root/backhaul.json..."
        if [ -d /root/backhaul ]; then
            sudo rm -rf /root/backhaul
            if [ $? -eq 0 ]; then
                echo "/root/backhaul directory removed successfully."
            else
                echo "Failed to remove /root/backhaul directory. Exiting..."
                exit 1
            fi
        else
            echo "/root/backhaul directory does not exist. Skipping removal."
        fi

        if [ -f /root/backhaul.json ]; then
            sudo rm -f /root/backhaul.json
            if [ $? -eq 0 ]; then
                echo "/root/backhaul.json removed successfully."
            else
                echo "Failed to remove /root/backhaul.json. Exiting..."
                exit 1
            fi
        else
            echo "/root/backhaul.json does not exist. Skipping removal."
        fi

        echo "Tunnel removal completed."
        ;;
    *)
        echo "Invalid choice. Please select 1, 2, or 3."
        exit 1
        ;;
esac

echo "Script execution completed."
