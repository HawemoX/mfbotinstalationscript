#!/bin/bash

################################################################################
# Magical Fidget Bot (MFBot) Linux Installation Script
# 
# This script installs:
# - MFBot Console (latest version)
# - .NET 6 Runtime (required dependency)
# - Python Web Interface
# - All required dependencies
#
# Usage: sudo bash install_mfbot.sh
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation directory
INSTALL_DIR="/opt/mfbot"
WEB_DIR="$INSTALL_DIR/webinterface"

# Configuration
DEFAULT_BOT_PORT=8443
DEFAULT_WEB_PORT=8050

################################################################################
# Helper Functions
################################################################################

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

detect_architecture() {
    local arch=$(uname -m)
    print_info "Detected architecture: $arch"
    
    case $arch in
        x86_64|amd64)
            BOT_ARCH="x86_64"
            ;;
        aarch64|arm64)
            BOT_ARCH="ARM64"
            ;;
        armv7l)
            BOT_ARCH="ARMRasp"
            ;;
        armv6l)
            BOT_ARCH="ARMRasp"
            ;;
        armhf)
            BOT_ARCH="ARM"
            ;;
        i386|i686)
            BOT_ARCH="i686"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
    
    print_success "Will download MFBot for architecture: $BOT_ARCH"
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
        print_info "Detected distribution: $DISTRO $VERSION"
    else
        print_warning "Cannot detect distribution, assuming Debian-based"
        DISTRO="debian"
    fi
}

################################################################################
# Installation Functions
################################################################################

install_dependencies() {
    print_header "Installing System Dependencies"
    
    case $DISTRO in
        ubuntu|debian|raspbian)
            print_info "Updating package lists..."
            apt-get update -qq
            
            print_info "Installing required packages..."
            apt-get install -y \
                wget \
                curl \
                unzip \
                python3 \
                python3-pip \
                python3-venv \
                ca-certificates \
                gnupg \
                software-properties-common
            ;;
        fedora|rhel|centos)
            print_info "Installing required packages..."
            dnf install -y \
                wget \
                curl \
                unzip \
                python3 \
                python3-pip \
                ca-certificates
            ;;
        arch|manjaro)
            print_info "Installing required packages..."
            pacman -Sy --noconfirm \
                wget \
                curl \
                unzip \
                python \
                python-pip
            ;;
        *)
            print_warning "Unknown distribution. Please install wget, curl, unzip, python3, and python3-pip manually."
            ;;
    esac
    
    print_success "System dependencies installed"
}

install_dotnet() {
    print_header "Installing .NET Runtime"
    
    # Check if .NET is already installed (6 or higher)
    if command -v dotnet &> /dev/null; then
        local dotnet_version=$(dotnet --version 2>/dev/null | cut -d. -f1)
        if [ "$dotnet_version" -ge "6" ] 2>/dev/null; then
            print_success ".NET runtime already installed (version $dotnet_version)"
            return
        fi
    fi
    
    print_info "Installing .NET runtime..."
    
    case $DISTRO in
        ubuntu|debian)
            # Add Microsoft package repository
            print_info "Adding Microsoft package repository..."
            wget -q https://packages.microsoft.com/config/$DISTRO/$VERSION/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb 2>/dev/null || {
                print_warning "Unable to add Microsoft repository for this version"
                print_info "Using Microsoft's install script instead..."
                
                # Use Microsoft's universal install script
                wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
                chmod +x /tmp/dotnet-install.sh
                /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /usr/share/dotnet
                
                # Create symlink
                ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
                
                rm /tmp/dotnet-install.sh
                
                if command -v dotnet &> /dev/null; then
                    print_success ".NET runtime installed via install script"
                    return
                else
                    print_error ".NET installation failed"
                    exit 1
                fi
            }
            
            dpkg -i /tmp/packages-microsoft-prod.deb 2>/dev/null
            rm /tmp/packages-microsoft-prod.deb
            
            print_info "Updating package cache..."
            apt-get update -qq 2>/dev/null
            
            # Check what's actually available
            print_info "Checking available .NET versions..."
            
            # Try .NET 8 first (Ubuntu 24.04 and newer)
            if apt-cache policy dotnet-runtime-8.0 2>/dev/null | grep -q "Candidate:"; then
                print_info "Installing .NET 8 runtime..."
                if apt-get install -y dotnet-runtime-8.0 2>&1; then
                    print_success ".NET 8 installed successfully"
                else
                    print_warning ".NET 8 installation failed, trying alternate method..."
                    wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
                    chmod +x /tmp/dotnet-install.sh
                    /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /usr/share/dotnet
                    ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
                    rm /tmp/dotnet-install.sh
                fi
            # Fall back to .NET 6 for older versions
            elif apt-cache policy dotnet-runtime-6.0 2>/dev/null | grep -q "Candidate:"; then
                print_info "Installing .NET 6 runtime..."
                apt-get install -y dotnet-runtime-6.0
            else
                print_warning ".NET not available in repositories, using Microsoft's install script..."
                
                wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
                chmod +x /tmp/dotnet-install.sh
                /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /usr/share/dotnet
                
                ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
                rm /tmp/dotnet-install.sh
            fi
            ;;
        fedora|rhel|centos)
            # Try .NET 8 first, fall back to 6
            if dnf list dotnet-runtime-8.0 &> /dev/null; then
                dnf install -y dotnet-runtime-8.0
            else
                dnf install -y dotnet-runtime-6.0
            fi
            ;;
        *)
            print_warning "Unknown distribution. Using Microsoft's install script..."
            wget https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
            chmod +x /tmp/dotnet-install.sh
            /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /usr/share/dotnet
            
            ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
            rm /tmp/dotnet-install.sh
            ;;
    esac
    
    # Verify installation
    if command -v dotnet &> /dev/null; then
        print_success ".NET runtime installed successfully"
    else
        print_error ".NET installation failed"
        print_info "Please install .NET manually from: https://dotnet.microsoft.com/download"
        exit 1
    fi
}

create_directories() {
    print_header "Creating Installation Directories"
    
    print_info "Creating directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    
    print_info "Creating directory: $WEB_DIR"
    mkdir -p "$WEB_DIR"
    
    print_success "Directories created"
}

download_mfbot() {
    print_header "Downloading MFBot Console"
    
    local download_url="https://download.mfbot.de/latest/MFBot_Konsole_${BOT_ARCH}"
    
    print_info "Downloading from: $download_url"
    wget -q --show-progress -O "$INSTALL_DIR/MFBot" "$download_url"
    
    # Make executable
    chmod +x "$INSTALL_DIR/MFBot"
    
    print_success "MFBot downloaded successfully"
}

download_webinterface() {
    print_header "Downloading Web Interface"
    
    local web_url="https://download.mfbot.de/v5.0.0.4/mfbot-webinterface.zip"
    
    print_info "Downloading web interface..."
    if wget -q --show-progress -O /tmp/mfbot-webinterface.zip "$web_url" 2>&1; then
        # Verify it's actually a zip file
        if file /tmp/mfbot-webinterface.zip | grep -q "Zip archive"; then
            print_info "Extracting web interface..."
            unzip -q -o /tmp/mfbot-webinterface.zip -d "$WEB_DIR"
            rm /tmp/mfbot-webinterface.zip
            print_success "Web interface downloaded and extracted"
        else
            print_warning "Downloaded file is not a valid zip archive"
            print_info "Creating basic web interface setup..."
            create_basic_webinterface
        fi
    else
        print_warning "Web interface download failed"
        print_info "Creating basic web interface setup..."
        create_basic_webinterface
    fi
}

create_basic_webinterface() {
    print_info "Setting up minimal web interface..."
    
    # Create requirements.txt
    cat > "$WEB_DIR/requirements.txt" << 'EOF'
pandas>=0.23.0
plotly>=2.7.0
dash==2.14.2
dash-bootstrap-components>=1.0.0
requests>=2.26.0
flask>=2.0.0
colorama>=0.4.0
EOF

    # Create a basic MainProgram.py
    cat > "$WEB_DIR/MainProgram.py" << 'EOFPY'
#!/usr/bin/env python3
"""
Basic MFBot Web Interface
This is a minimal fallback interface created by the installation script.
"""

import argparse
import sys
from flask import Flask, render_template_string, request, redirect, session
import requests
import json
from functools import wraps

app = Flask(__name__)
app.secret_key = 'mfbot-web-interface-secret-key-change-me'

# Global configuration
BOT_API_URL = None
REMOTE_USER = None
REMOTE_PASS = None
WEB_USER = None
WEB_PASS = None

def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('logged_in'):
            return redirect('/login')
        return f(*args, **kwargs)
    return decorated

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        if username == WEB_USER and password == WEB_PASS:
            session['logged_in'] = True
            return redirect('/')
        return render_template_string(LOGIN_TEMPLATE, error="Invalid credentials")
    return render_template_string(LOGIN_TEMPLATE)

@app.route('/logout')
def logout():
    session.pop('logged_in', None)
    return redirect('/login')

@app.route('/')
@requires_auth
def index():
    try:
        # Try to connect to bot
        response = requests.get(f"{BOT_API_URL}/status", 
                              auth=(REMOTE_USER, REMOTE_PASS),
                              timeout=5)
        if response.status_code == 200:
            status = "Connected"
            status_class = "success"
        else:
            status = "Connection Error"
            status_class = "warning"
    except:
        status = "Cannot connect to bot"
        status_class = "danger"
    
    return render_template_string(MAIN_TEMPLATE, 
                                 bot_url=BOT_API_URL,
                                 status=status,
                                 status_class=status_class)

LOGIN_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>MFBot Web Interface - Login</title>
    <style>
        body { font-family: Arial, sans-serif; background: #f0f0f0; margin: 0; padding: 0; }
        .container { max-width: 400px; margin: 100px auto; background: white; padding: 30px; border-radius: 5px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; text-align: center; }
        input { width: 100%; padding: 10px; margin: 10px 0; border: 1px solid #ddd; border-radius: 3px; box-sizing: border-box; }
        button { width: 100%; padding: 12px; background: #007bff; color: white; border: none; border-radius: 3px; cursor: pointer; font-size: 16px; }
        button:hover { background: #0056b3; }
        .error { color: red; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🤖 MFBot Web Interface</h1>
        {% if error %}<p class="error">{{ error }}</p>{% endif %}
        <form method="post">
            <input type="text" name="username" placeholder="Username" required>
            <input type="password" name="password" placeholder="Password" required>
            <button type="submit">Login</button>
        </form>
    </div>
</body>
</html>
'''

MAIN_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>MFBot Web Interface</title>
    <style>
        body { font-family: Arial, sans-serif; background: #f0f0f0; margin: 0; padding: 0; }
        .header { background: #007bff; color: white; padding: 20px; }
        .container { max-width: 1200px; margin: 20px auto; padding: 20px; }
        .card { background: white; padding: 20px; margin: 10px 0; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .status-success { color: green; }
        .status-warning { color: orange; }
        .status-danger { color: red; }
        a { color: #007bff; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .info { background: #e7f3ff; padding: 15px; border-left: 4px solid #007bff; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🤖 MFBot Web Interface</h1>
        <a href="/logout" style="color: white; float: right;">Logout</a>
    </div>
    <div class="container">
        <div class="card">
            <h2>Connection Status</h2>
            <p><strong>Bot API:</strong> {{ bot_url }}</p>
            <p><strong>Status:</strong> <span class="status-{{ status_class }}">{{ status }}</span></p>
        </div>
        
        <div class="info">
            <h3>⚠️ Basic Web Interface</h3>
            <p>This is a minimal fallback web interface created by the installation script.</p>
            <p><strong>The full web interface could not be downloaded.</strong></p>
            <p>This basic interface only provides connection status. For full functionality:</p>
            <ol>
                <li>Download the web interface manually from: <a href="https://download.mfbot.de/v5.0.0.4/mfbot-webinterface.zip" target="_blank">here</a></li>
                <li>Extract it to: <code>/opt/mfbot/webinterface/</code></li>
                <li>Restart the web interface service</li>
            </ol>
            <p>Or check the MFBot forum for alternative web interfaces or Docker solutions.</p>
        </div>

        <div class="card">
            <h2>Quick Links</h2>
            <ul>
                <li><a href="https://www.mfbot.de/en/" target="_blank">MFBot Official Site</a></li>
                <li><a href="https://forum.mfbot.de/" target="_blank">MFBot Forum</a></li>
                <li><a href="https://github.com/mangunowsky/MFBotDocker" target="_blank">MFBot Docker (Alternative)</a></li>
            </ul>
        </div>
    </div>
</body>
</html>
'''

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='MFBot Web Interface (Basic)')
    parser.add_argument('-a', '--address', required=True, help='Bot API address (e.g., http://127.0.0.1:8443)')
    parser.add_argument('--remoteU', required=True, help='Bot remote username')
    parser.add_argument('--remoteP', required=True, help='Bot remote password')
    parser.add_argument('--webU', required=True, help='Web interface username')
    parser.add_argument('--webP', required=True, help='Web interface password')
    parser.add_argument('--port', type=int, default=8050, help='Web interface port')
    parser.add_argument('--debug', type=int, default=0, help='Debug mode')
    
    args = parser.parse_args()
    
    BOT_API_URL = args.address.rstrip('/')
    REMOTE_USER = args.remoteU
    REMOTE_PASS = args.remoteP
    WEB_USER = args.webU
    WEB_PASS = args.webP
    
    print(f"Starting MFBot Web Interface (Basic) on port {args.port}")
    print(f"Bot API: {BOT_API_URL}")
    print(f"Access at: http://localhost:{args.port}")
    
    app.run(host='0.0.0.0', port=args.port, debug=(args.debug == 1))
EOFPY

    chmod +x "$WEB_DIR/MainProgram.py"
    
    print_success "Basic web interface created"
}

setup_python_environment() {
    print_header "Setting Up Python Environment for Web Interface"
    
    print_info "Creating Python virtual environment..."
    python3 -m venv "$WEB_DIR/venv"
    
    print_info "Installing Python dependencies..."
    "$WEB_DIR/venv/bin/pip" install --quiet --upgrade pip
    
    if [ -f "$WEB_DIR/requirements.txt" ]; then
        print_info "Installing from requirements.txt..."
        "$WEB_DIR/venv/bin/pip" install --quiet -r "$WEB_DIR/requirements.txt" 2>&1 | grep -v "Requirement already satisfied" || true
        print_success "Python dependencies installed"
    else
        print_warning "requirements.txt not found"
        print_info "Installing basic dependencies..."
        "$WEB_DIR/venv/bin/pip" install --quiet flask requests
        print_success "Basic Python dependencies installed"
    fi
}

create_config_file() {
    print_header "Creating Configuration File"
    
    cat > "$INSTALL_DIR/config.ini" << EOF
# MFBot Configuration File
# Edit this file to configure your bot settings

[Remote Access]
Enabled=true
Port=$DEFAULT_BOT_PORT
Username=admin
Password=changeme

[Web Interface]
Enabled=true
Port=$DEFAULT_WEB_PORT
Username=web
Password=changeme

# Note: After first run, account settings will be stored in Acc.ini
EOF
    
    print_success "Configuration file created at $INSTALL_DIR/config.ini"
}

create_start_scripts() {
    print_header "Creating Start Scripts"
    
    # Bot start script
    cat > "$INSTALL_DIR/start_bot.sh" << 'EOF'
#!/bin/bash

# MFBot Start Script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting MFBot Console..."
cd "$SCRIPT_DIR"
./MFBot
EOF
    chmod +x "$INSTALL_DIR/start_bot.sh"
    
    # Web interface start script
    cat > "$INSTALL_DIR/start_webui.sh" << EOF
#!/bin/bash

# MFBot Web Interface Start Script
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="\$SCRIPT_DIR/webinterface"

# Default configuration - edit these values
BOT_HOST="http://127.0.0.1:$DEFAULT_BOT_PORT"
BOT_USER="admin"
BOT_PASS="changeme"
WEB_USER="web"
WEB_PASS="changeme"
WEB_PORT="$DEFAULT_WEB_PORT"

echo "Starting MFBot Web Interface..."
echo "Web UI will be available at: http://localhost:\$WEB_PORT"
echo ""

cd "\$WEB_DIR"
source venv/bin/activate

python MainProgram.py \\
    -a "\$BOT_HOST" \\
    --remoteU="\$BOT_USER" \\
    --remoteP="\$BOT_PASS" \\
    --webU="\$WEB_USER" \\
    --webP="\$WEB_PASS" \\
    --port="\$WEB_PORT"
EOF
    chmod +x "$INSTALL_DIR/start_webui.sh"
    
    # Combined start script
    cat > "$INSTALL_DIR/start_all.sh" << 'EOF'
#!/bin/bash

# Start MFBot and Web Interface
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting MFBot services..."

# Start bot in background
"$SCRIPT_DIR/start_bot.sh" &
BOT_PID=$!

echo "MFBot started with PID: $BOT_PID"
sleep 3

# Start web interface
"$SCRIPT_DIR/start_webui.sh"
EOF
    chmod +x "$INSTALL_DIR/start_all.sh"
    
    print_success "Start scripts created"
}

create_systemd_service() {
    print_header "Creating Systemd Service (Optional)"
    
    cat > /etc/systemd/system/mfbot.service << EOF
[Unit]
Description=Magical Fidget Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/MFBot
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/mfbot-webui.service << EOF
[Unit]
Description=MFBot Web Interface
After=network.target mfbot.service
Requires=mfbot.service

[Service]
Type=simple
User=root
WorkingDirectory=$WEB_DIR
ExecStart=$INSTALL_DIR/start_webui.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    
    print_success "Systemd services created (not enabled by default)"
    print_info "To enable automatic startup, run:"
    print_info "  sudo systemctl enable mfbot"
    print_info "  sudo systemctl enable mfbot-webui"
}

create_docker_compose() {
    print_header "Creating Docker Compose File (Optional)"
    
    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  mfbot:
    image: mono:latest
    container_name: mfbot
    volumes:
      - $INSTALL_DIR:/app
    working_dir: /app
    command: ./MFBot
    restart: unless-stopped
    ports:
      - "$DEFAULT_BOT_PORT:$DEFAULT_BOT_PORT"

  mfbot-webui:
    image: python:3.9-slim
    container_name: mfbot-webui
    volumes:
      - $WEB_DIR:/app
    working_dir: /app
    command: bash -c "pip install -r requirements.txt && python MainProgram.py -a http://mfbot:$DEFAULT_BOT_PORT --remoteU=admin --remoteP=changeme --webU=web --webP=changeme --port=$DEFAULT_WEB_PORT"
    restart: unless-stopped
    ports:
      - "$DEFAULT_WEB_PORT:$DEFAULT_WEB_PORT"
    depends_on:
      - mfbot

EOF
    
    print_success "Docker Compose file created (for advanced users)"
}

print_final_instructions() {
    print_header "Installation Complete!"
    
    echo ""
    echo -e "${GREEN}MFBot has been successfully installed!${NC}"
    echo ""
    echo -e "${YELLOW}Installation Directory:${NC} $INSTALL_DIR"
    echo ""
    echo -e "${YELLOW}Quick Start Guide:${NC}"
    echo ""
    echo "1. Configure your bot:"
    echo "   Edit: $INSTALL_DIR/config.ini"
    echo "   Or after first run: $INSTALL_DIR/Acc.ini"
    echo ""
    echo "2. Start the bot only:"
    echo "   cd $INSTALL_DIR"
    echo "   ./start_bot.sh"
    echo ""
    echo "3. Start the web interface only:"
    echo "   cd $INSTALL_DIR"
    echo "   ./start_webui.sh"
    echo "   Then open: http://localhost:$DEFAULT_WEB_PORT"
    echo ""
    echo "4. Start both bot and web interface:"
    echo "   cd $INSTALL_DIR"
    echo "   ./start_all.sh"
    echo ""
    echo -e "${YELLOW}Systemd Service (optional):${NC}"
    echo "   sudo systemctl start mfbot"
    echo "   sudo systemctl start mfbot-webui"
    echo "   sudo systemctl enable mfbot  # Auto-start on boot"
    echo ""
    echo -e "${YELLOW}Default Credentials:${NC}"
    echo "   Bot Remote Access:"
    echo "     Username: admin"
    echo "     Password: changeme"
    echo "     Port: $DEFAULT_BOT_PORT"
    echo ""
    echo "   Web Interface:"
    echo "     Username: web"
    echo "     Password: changeme"
    echo "     Port: $DEFAULT_WEB_PORT"
    echo ""
    echo -e "${RED}IMPORTANT: Change default passwords before exposing to network!${NC}"
    echo ""
    echo -e "${YELLOW}Documentation:${NC}"
    echo "   Official site: https://www.mfbot.de/"
    echo "   Forum: https://forum.mfbot.de/"
    echo ""
    echo -e "${GREEN}Enjoy using MFBot!${NC}"
    echo ""
}

################################################################################
# Main Installation Process
################################################################################

main() {
    print_header "Magical Fidget Bot - Linux Installation Script"
    
    check_root
    detect_distro
    detect_architecture
    
    install_dependencies
    install_dotnet
    create_directories
    download_mfbot
    download_webinterface
    setup_python_environment
    create_config_file
    create_start_scripts
    create_systemd_service
    create_docker_compose
    
    print_final_instructions
}

# Run main installation
main "$@"
