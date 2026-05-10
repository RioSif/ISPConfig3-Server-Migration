#!/bin/bash
#
  echo "###############################################################"
  echo "##                     Welcome                               ##"
  echo "##   Please take note of all instructions and                ##"
  echo "##   recommendations                                         ##"
  echo "##                                                           ##"
  echo "##   If you have questions or problems you can always        ##"
  echo "##   visit http://wiki.teris-cooper.de                       ##"
  echo "##                                                           ##"
  echo "##   Alternatively you're welcome to send an email to        ##"
  echo "##   admin [at] teris-cooper [dot] de                        ##"
  echo "###############################################################"
  echo ""

#common_args='-aPv --delete'
#common_args='-aPv --dry-run'
common_args='-aPv --compress'
install_rsync="apt-get -y install rsync"
db_start="service mysql start"
db_stop="service mysql stop"

function test_ssh_connection {
  local server="$1"
  ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o BatchMode=yes "$server" "echo Test connection successful" 2>/dev/null
  return $?
}

function setup_ssh_keys {
    clear
    echo "###############################################################"
    echo "##             SSH Key Setup                               ##"
    echo "###############################################################"
    echo ""
    
    SSH_KEY="$HOME/.ssh/id_rsa"
    
    # Check if SSH key already exists
    if [[ -f "$SSH_KEY" ]]; then
        echo "✓ SSH key already exists at $SSH_KEY"
        echo ""
    else
        echo "SSH key not found. Generating new SSH key pair..."
        mkdir -p "$HOME/.ssh"
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N ""
        chmod 700 "$HOME/.ssh"
        chmod 600 "$SSH_KEY"
        echo "✓ SSH key generated at $SSH_KEY"
        echo ""
    fi
    
    echo "Testing SSH key connection..."
    if test_ssh_connection "$main_server"; then
        echo "✓ SSH key authentication is working!"
        echo ""
    else
        echo "⚠ SSH key connection failed. Attempting to copy key to remote server..."
        echo "Please enter the root password for the remote server:"
        read -s ssh_setup_password
        echo ""
        
        if [[ -z "$ssh_setup_password" ]]; then
            echo "Password empty. Skipping SSH key copy."
            echo "You can copy it manually later:"
            cat "$SSH_KEY.pub"
            echo ""
        else
            # Ensure sshpass is installed
            if ! command -v sshpass >/dev/null 2>&1; then
                echo "Installing sshpass for secure password handling..."
                apt-get update >/dev/null 2>&1 && apt-get install -y sshpass >/dev/null 2>&1
            fi
            
            # Use sshpass for non-interactive password authentication
            if command -v sshpass >/dev/null 2>&1; then
                echo "Copying SSH public key to remote server..."
                
                # Use sshpass with piped public key for key installation
                local sshpass_output
                sshpass_output=$(cat "$SSH_KEY.pub" | SSHPASS="$ssh_setup_password" sshpass -e ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no "root@$main_server" "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>&1)
                local install_result=$?
                
                if [ $install_result -eq 0 ]; then
                    echo "✓ SSH public key copied to remote server"
                    echo ""
                    
                    # Test again after copying
                    sleep 2
                    if test_ssh_connection "root@$main_server"; then
                        echo "✓ SSH key authentication is now working!"
                        echo ""
                    else
                        echo "⚠ SSH key test connection failed. Check your credentials and try again."
                        echo ""
                    fi
                else
                    echo "⚠ Failed to copy SSH key to remote server."
                    echo "Debug info: $sshpass_output"
                    echo "Please ensure:"
                    echo "  1. The password is correct"
                    echo "  2. SSH is running on the remote server"
                    echo "  3. The remote server allows root login"
                    echo ""
                fi
            else
                echo "Error: Could not install sshpass. SSH key copy cannot proceed without it."
                echo "Please install sshpass manually with: apt-get install -y sshpass"
                echo ""
            fi
        fi
        
        unset ssh_setup_password
    fi
}

echo "Please enter the IP address of your master (remote) server:"
read main_server
echo ""

echo "Which web server is installed on the remote server?"
echo ""
echo "  (1) Nginx"
echo "  (2) Apache"
echo ""
read -p "Select web server (1 or 2): " WEBSERVER_CHOICE

if [[ "$WEBSERVER_CHOICE" == "1" ]]; then
    WEBSERVER_TYPE="nginx"
    www_start="service nginx start"
    www_stop="service nginx stop"
elif [[ "$WEBSERVER_CHOICE" == "2" ]]; then
    WEBSERVER_TYPE="apache2"
    www_start="service apache2 start"
    www_stop="service apache2 stop"
else
    echo "⚠ Invalid selection. Using Nginx as default."
    WEBSERVER_TYPE="nginx"
    www_start="service nginx start"
    www_stop="service nginx stop"
fi

echo "Using web server: $WEBSERVER_TYPE"
echo ""

setup_ssh_keys

function menu {
    clear
    echo "###############################################################"
    echo "##           ISPConfig Server Migration Tool                 ##"
    echo "##                    Main Menu                              ##"
    echo "###############################################################"
    echo "##                                                           ##"
    echo "## PREPARATION:                                              ##"
    echo "## Install RSync on the remote server                  (1)   ##"
    echo "## Change server hostname                              (2)   ##"
    echo "## Update the server                                   (3)   ##"
    echo "## Install ISPConfig                                   (4)   ##"
    echo "## Reboot the server                                   (5)   ##"
    echo "##                                                           ##"
    echo "## DATABASE & CONFIG:                                        ##"
    echo "## Synchronize MySql databases                         (6)   ##"
    echo "## Update ISPConfig MySQL Password                     (7)   ##"
    echo "##                                                           ##"
    echo "## DATA MIGRATION:                                           ##"
    echo "## Synchronize websites (/var/www, configs, logs)      (8)   ##"
    echo "## Synchronize email (/var/vmail, logs)                (9)   ##"
    echo "## Export users, groups & system files                 (a)   ##"
    echo "## Import exported users & groups (after step 6)       (b)   ##"
    echo "## Synchronize ACME certificates                       (c)   ##"
    echo "##                                                           ##"
    echo "## CLEANUP:                                                  ##"
    echo "## Delete SSH key from remote server                   (d)   ##"
    echo "## Exit program                                        (0)   ##"
    echo "###############################################################"
    read -n 1 input
}

    function pause_before_menu {
      echo ""
      read -p "Press Enter to return to menu..." _
      menu
    }

function install {
    clear
    echo "###############################################################"
    echo "##         Installing RSync on Remote Server                 ##"
    echo "###############################################################"
    echo ""
    echo "RSync is required to efficiently transfer large amounts of data."
    echo "Installing on: $main_server"
    echo ""
    ssh $main_server "$install_rsync"
    echo ""
    echo "✓ RSync installation complete"
    echo ""
    echo "The remote server is now ready for migration."
    echo "###############################################################"
      pause_before_menu
}

  function detect_primary_ip {
    local detected_ip=""

    detected_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')

    if [[ -z "$detected_ip" ]]; then
      detected_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    echo "$detected_ip"
  }

function ask_yes_no {
    local prompt="$1"
    local default="$2"
    local response
    
    read -p "$prompt" response
    
    if [[ "$response" == "y" || "$response" == "Y" ]]; then
        return 0
    else
        return 1
    fi
}

function change_hostname {
    clear
    echo "###############################################################"
    echo "##              Change Server Hostname                       ##"
    echo "###############################################################"
    echo ""
    echo "Current hostname on this server:"
    hostname
    echo ""
    echo "This will change the hostname on the local server to match"
    echo "the remote server's hostname."
    echo ""
    echo "Remote server: $main_server"
    echo ""
    
    # Get the remote server's hostname
    REMOTE_HOSTNAME=$(ssh $main_server "hostname" 2>/dev/null)
    
    if [[ -z "$REMOTE_HOSTNAME" ]]; then
        echo "⚠ Could not retrieve remote server hostname."
        echo "Please ensure SSH connection is working."
        echo ""
        pause_before_menu
        return
    fi
    
    echo "Remote server hostname: $REMOTE_HOSTNAME"
    echo ""
    read -p "Use the remote hostname '$REMOTE_HOSTNAME'? (y/n): " confirm

    local target_hostname=""
    local short_hostname=""
    local fqdn_hostname=""
    local public_ip=""

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      target_hostname="$REMOTE_HOSTNAME"
    else
      local detected_ip
      detected_ip=$(detect_primary_ip)

      echo ""
      if [[ -n "$detected_ip" ]]; then
        echo "Detected local source IP: $detected_ip"
        read -p "Use this IP as the local server public IP? (y/n): " use_detected_ip
        if [[ "$use_detected_ip" == "y" || "$use_detected_ip" == "Y" ]]; then
          public_ip="$detected_ip"
        fi
      fi

      if [[ -z "$public_ip" ]]; then
        read -p "Enter the local server public IP: " public_ip
      fi

      while [[ -z "$short_hostname" ]]; do
        read -p "Enter the hostname (for example: server): " short_hostname
      done

      while [[ -z "$fqdn_hostname" ]]; do
        read -p "Enter the fully qualified hostname (for example: server.example.com): " fqdn_hostname
      done

      target_hostname="$short_hostname"
    fi

    echo ""
    echo "Changing hostname to: $target_hostname"
    hostnamectl set-hostname "$target_hostname" 2>/dev/null

    if [[ $? -eq 0 ]]; then
      if [[ -n "$public_ip" && -n "$fqdn_hostname" && -n "$short_hostname" ]]; then
        local hosts_backup="/etc/hosts.backup.$(date +%s)"
        cp /etc/hosts "$hosts_backup"

        if grep -qE "^[[:space:]]*$public_ip[[:space:]]" /etc/hosts; then
          sed -i "s|^[[:space:]]*$public_ip[[:space:]].*|$public_ip $fqdn_hostname $short_hostname|" /etc/hosts
        else
          echo "$public_ip $fqdn_hostname $short_hostname" >> /etc/hosts
        fi

        echo "✓ /etc/hosts updated with FQDN (backup: $hosts_backup)"
        echo ""
      fi

      echo "✓ Hostname changed successfully!"
      echo ""
      echo "New hostname:"
      hostname
      echo ""
      echo "Note: You may need to log out and back in for the prompt to update."
    else
      echo "⚠ Failed to change hostname."
      echo "Try running: sudo hostnamectl set-hostname $target_hostname"
    fi
    echo ""
    echo "###############################################################"
    echo ""
    pause_before_menu
}

function update_server {
    clear
    echo "###############################################################"
    echo "##            Update Server Packages                         ##"
    echo "###############################################################"
    echo ""
    echo "This will update all packages on this server to the latest"
    echo "versions available in the repositories."
    echo ""
    echo "Commands to run:"
    echo "  1. apt-get update"
    echo "  2. apt-get upgrade"
    echo ""
    read -p "Proceed with server update? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Cancelled. No updates performed."
        echo ""
        pause_before_menu
        return
    fi
    
    echo ""
    echo "Updating package list..."
    apt-get update
    
    if [[ $? -ne 0 ]]; then
        echo "⚠ Error during apt-get update"
        pause_before_menu
        return
    fi
    
    echo ""
    echo "Upgrading packages..."
    apt-get upgrade -y
    
    if [[ $? -eq 0 ]]; then
        echo ""
        echo "✓ Server update completed successfully!"
    else
        echo ""
        echo "⚠ Some packages may not have been updated. Check the output above."
    fi
    
    echo ""
    echo "###############################################################"
    echo ""
    pause_before_menu
}

function reboot_server {
    clear
    echo "###############################################################"
    echo "##              Reboot Server                                ##"
    echo "###############################################################"
    echo ""
    echo "WARNING: This will reboot the server immediately!"
    echo ""
    echo "All running services will be stopped and the server will"
    echo "restart. This may interrupt any ongoing migrations or services."
    echo ""
    read -p "Are you sure you want to reboot? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo "Reboot cancelled."
        echo ""
        pause_before_menu
        return
    fi
    
    echo ""
    echo "Server is rebooting now..."
    echo ""
    shutdown -r now
}

function install_ispconfig {
    clear
    echo "###############################################################"
    echo "##            Install ISPConfig                              ##"
    echo "###############################################################"
    echo ""
    echo "This will install ISPConfig on this server."
    echo ""
    echo "Web server: $WEBSERVER_TYPE"
    echo ""
    
    local webserver_option=""
    if [[ "$WEBSERVER_TYPE" == "nginx" ]]; then
        webserver_option="--use-nginx"
    else
        webserver_option="--use-apache"
    fi
    
    echo "ISPConfig installation will now begin."
    echo "This may take several minutes. Please be patient."
    echo ""
    
    read -p "Ready to proceed? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Installation cancelled."
        echo ""
        pause_before_menu
        return
    fi
    
    echo ""
    echo "###############################################################"
    echo "Starting ISPConfig installation..."
    echo "###############################################################"
    echo ""
    
    wget -O - https://get.ispconfig.org | sh -s -- $webserver_option --use-ftp-ports=40110-40210 --unattended-upgrades
    
    if [[ $? -eq 0 ]]; then
        echo ""
        echo "###############################################################"
        echo "✓ ISPConfig installation completed successfully!"
        echo "###############################################################"
        echo ""
        echo "Your ISPConfig installation is now ready."
        echo "You can access it at: https://localhost:8080"
        echo ""
        echo "Default login credentials can be found in the ISPConfig documentation."
    else
        echo ""
        echo "###############################################################"
        echo "⚠ ISPConfig installation encountered an error."
        echo "###############################################################"
        echo ""
        echo "Please check the output above for details and try again."
    fi
    
    echo ""
    pause_before_menu
}

function db_migration {
  clear
  
  # Initialize error/warning log
  local ERROR_LOG=$(mktemp)
  local WARNING_LOG=$(mktemp)
  
  # Ask for MySQL passwords on first run
  if [[ -z "$remote_mysql_root_password" ]]; then
    echo "Please enter the MySQL root password for the remote server:"
    read -s remote_mysql_root_password
    echo ""
  fi
  
  if [[ -z "$local_mysql_root_password" ]]; then
    echo "Please enter the MySQL root password for this (local) server:"
    read -s local_mysql_root_password
    echo ""
  fi
  
  echo "###############################################################"
  echo "###############################################################"
  echo "##          MySQL Database Migration Process                 ##"
  echo "###############################################################"
  echo "##  This will:                                               ##"
  echo "##    1. Dump all databases from remote server               ##"
  echo "##    2. Copy the dump to this server                        ##"
  echo "##    3. Import all databases                                ##"
  echo "##    4. Upgrade MySQL system tables if needed               ##"
  echo "###############################################################"
  echo ""
  
  echo "Back up the remote databases............................................................."
  if ! ssh $main_server "mkdir -p /root/ispc-migr/mysql; MYSQL_PWD='$remote_mysql_root_password' mysqldump -u root --force --all-databases > /root/ispc-migr/mysql/fulldump.sql" 2>>$ERROR_LOG; then
    echo "⚠ Warning: Error during remote database backup" | tee -a $WARNING_LOG
  fi
  
  echo "Copy the backup.........................................................................."
  if ! rsync $common_args $main_server:/root/ispc-migr /root 2>>$ERROR_LOG; then
    echo "⚠ Warning: Error during rsync copy" | tee -a $WARNING_LOG
  fi
  
  echo "Import the backup........................................................................"
  if ! MYSQL_PWD='$local_mysql_root_password' mysql -u root < /root/ispc-migr/mysql/fulldump.sql 2>>$ERROR_LOG; then
    echo "⚠ Warning: Error during database import" | tee -a $WARNING_LOG
  fi
  
  echo "Upgrade mysql system tables if target server has newer mysql/mariadb versions..........................................................."
  if ! MYSQL_PWD='$local_mysql_root_password' mysql_upgrade -uroot --force 2>>$ERROR_LOG; then
    echo "⚠ Warning: Error during mysql_upgrade" | tee -a $WARNING_LOG
  fi
  
  echo ""
  echo "###############################################################"
  echo "###############################################################"
  echo "##             Database Migration Summary                    ##"
  echo "###############################################################"
  
  # Check if there are any errors or warnings
  if [[ -s "$ERROR_LOG" ]] || [[ -s "$WARNING_LOG" ]]; then
    echo "⚠ WARNINGS/ERRORS FOUND:"
    echo ""
    if [[ -s "$ERROR_LOG" ]]; then
      echo "--- Errors ---"
      cat "$ERROR_LOG"
      echo ""
    fi
    if [[ -s "$WARNING_LOG" ]]; then
      echo "--- Warnings ---"
      cat "$WARNING_LOG"
    fi
  else
    echo "✅ No warnings or errors found!"
  fi
  
  echo "###############################################################"
  echo ""
  
  # Cleanup temp files
  rm -f "$ERROR_LOG" "$WARNING_LOG"
  
  pause_before_menu
}

function update_ispconfig_password {
    clear
    echo "###############################################################"
    echo "###############################################################"
    echo "##    Update ISPConfig MySQL Database Credentials            ##"
    echo "###############################################################"
    echo ""
    echo "This sets the MySQL password for the 'ispconfig' database user"
    echo "to match the old server's credentials."
    echo ""
    
    # Ask for MySQL password if not already set
    if [[ -z "$local_mysql_root_password" ]]; then
        echo "Please enter the MySQL root password for this (local) server:"
        read -s local_mysql_root_password
        echo ""
    fi
    
    local ispconfig_config="/usr/local/ispconfig/interface/lib/config.inc.php"
    local new_ispconfig_password=""
    
    # Try to read password from config file
    if [[ -f "$ispconfig_config" ]]; then
        new_ispconfig_password=$(grep "\$conf\['db_password'\]" "$ispconfig_config" | cut -d"'" -f4 | head -1)
        
        if [[ -n "$new_ispconfig_password" ]]; then
            echo "Found ISPConfig password in config file."
            local first_char="${new_ispconfig_password:0:1}"
            local last_three="${new_ispconfig_password: -3}"
            local password_length=${#new_ispconfig_password}
            local masked=$(printf '%*s' $((password_length - 4)) | tr ' ' '*')
            echo "Found ISPConfig Password: $first_char$masked$last_three"
            echo ""
            read -p "Use this password to update MySQL? (y/n): " confirm
            
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo "Please enter the new ISPConfig MySQL password:"
                read -s new_ispconfig_password
                echo ""
            fi
        else
            echo "Could not extract password from config file. Please enter the new ISPConfig MySQL password:"
            read -s new_ispconfig_password
            echo ""
        fi
    else
        echo "Config file not found at $ispconfig_config"
        echo "Please enter the new ISPConfig MySQL password:"
        read -s new_ispconfig_password
        echo ""
    fi
    
    if [[ -z "$new_ispconfig_password" ]]; then
        echo "Password cannot be empty. Aborting."
        pause_before_menu
        return
    fi
    
    echo "Updating ISPConfig MySQL password..."
    MYSQL_PWD="$local_mysql_root_password" mysql -u root -e "SET PASSWORD FOR 'ispconfig'@'localhost' = PASSWORD('$new_ispconfig_password');" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        echo "✓ ISPConfig MySQL password updated successfully"
        echo ""
    else
        echo "⚠ Failed to update ISPConfig password. Check your credentials."
        pause_before_menu
        return
    fi
    
    echo "Running mysqlcheck for database integrity..."
    MYSQL_PWD="$local_mysql_root_password" mysqlcheck -u root -A --auto-repair
    
    echo ""
    echo "###############################################################"
    echo "ISPConfig password update complete!"
    echo "###############################################################"
    echo "NOTE: If you changed the password, update the config file:"
    echo "  - /usr/local/ispconfig/interface/lib/config.inc.php"
    echo "  - Any other files that reference the ispconfig MySQL user"
    echo ""
    echo "Now ISPConfig's new server's credentianls are the same as old server's password" 
    echo "###############################################################"
    echo ""
    
    unset new_ispconfig_password
    pause_before_menu
}

function www_migration {
    clear

  echo "###############################################################"
  echo "###############################################################"
  echo "##       Website & Web Server Configuration Sync             ##"
  echo "###############################################################"
  echo "##  This will sync:                                          ##"
  echo "##    - /var/www/ (all website files)                        ##"
  echo "##    - Web server vhost configs (sites-available/enabled)   ##"
  echo "##    - Custom web server configurations                     ##"
  echo "##    - Web server logs                                      ##"
  echo "###############################################################"
  echo ""
  
  echo "Stopping web server ($WEBSERVER_TYPE)..."
  $www_stop
  echo "✓ Web server stopped"
  echo ""
  
  echo "Syncing website files from /var/www/..."
  rsync $common_args $main_server:/var/www/ /var/www
  echo "✓ Website files synced"
  echo ""
  
  echo "Syncing web server logs..."
  rsync $common_args $main_server:/var/log/ispconfig/httpd/ /var/log/ispconfig/httpd
  echo "✓ Logs synced"
  echo ""
  
  echo "Syncing $WEBSERVER_TYPE configurations..."
  if [[ "$WEBSERVER_TYPE" == "nginx" ]]; then
    rsync $common_args --exclude='acme.vhost' --exclude='apps.vhost' --exclude='default' --exclude='ispconfig.vhost' $main_server:/etc/nginx/sites-available/ /etc/nginx/sites-available
    rsync $common_args --exclude='000-apps.vhost' --exclude='000-ispconfig.vhost' --exclude='999-acme.vhost' --exclude='default' $main_server:/etc/nginx/sites-enabled/ /etc/nginx/sites-enabled
    rsync $common_args $main_server:/etc/nginx/custom /etc/nginx 2>/dev/null || true
    rsync $common_args $main_server:/etc/nginx/services /etc/nginx 2>/dev/null || true
  else
    rsync $common_args --exclude='000-' $main_server:/etc/apache2/sites-available/ /etc/apache2/sites-available
    rsync $common_args --exclude='000-' $main_server:/etc/apache2/sites-enabled/ /etc/apache2/sites-enabled
  fi
  echo "✓ $WEBSERVER_TYPE configurations synced"
  echo ""
  
  echo "Starting web server..."
  $www_start
  echo "✓ Web server started"
  echo ""
  echo "###############################################################"
  echo "✓ Website synchronization completed successfully!"
  echo "###############################################################"
      pause_before_menu
}

function mail_migration {
    clear
  echo "###############################################################"
  echo "###############################################################"
  echo "##           Email & Virtual Mailbox Synchronization         ##"
  echo "###############################################################"
  echo "##  This will sync:                                          ##"
  echo "##    - /var/vmail/ (virtual mailbox data)                   ##"
  echo "##    - Mail server logs                                     ##"
  echo "###############################################################"
  echo ""
  
  echo "Syncing virtual mailbox data from /var/vmail/..."
  rsync $common_args $main_server:/var/vmail/ /var/vmail
  echo "✓ Virtual mailbox data synced"
  echo ""
  
  echo "Syncing mail server logs..."
  rsync $common_args $main_server:/var/log/mail.* /var/log/
  echo "✓ Mail logs synced"
  echo ""
  echo "###############################################################"
  echo "✓ Email synchronization completed successfully!"
  echo "###############################################################"
      pause_before_menu
}

function files_migration {
    clear
  echo "###############################################################"
  echo "###############################################################"
  echo "############# Files Migration                           #######"
  echo "############# Step1:                                    #######"
  echo "############# Copy /var/backup                          #######"
  echo "###############################################################"
  echo "############# Step2:                                    #######"
  echo "############# Copy /etc/passwd to /root/ispc-migr/files #######"
  echo "###############################################################"
  echo "############# Step3:                                    #######"
  echo "############# Copy /etc/group to /root/ispc-migr/files  #######"
  echo "###############################################################"
  echo "############# Step4:                                    #######"
  echo "############# Import users+passwords (option 7 in menu) #######"
  echo "###############################################################"
  echo "###############################################################"
  mkdir -p /root/ispc-migr/files
  
  echo "Copying backup directory..."
  rsync $common_args $main_server:/var/backup/ /var/backup
  
  echo "Copying system files (passwd, group, shadow, gshadow)..."
  rsync $common_args $main_server:/etc/passwd /root/ispc-migr/files/
  rsync $common_args $main_server:/etc/group  /root/ispc-migr/files/
  rsync $common_args $main_server:/etc/shadow  /root/ispc-migr/files/
  rsync $common_args $main_server:/etc/gshadow  /root/ispc-migr/files/
  echo ""
  echo "###############################################################"
  echo "Filtering users (UID >= $UGIDLIMIT) for migration..."
  echo "###############################################################"
  awk -v LIMIT=$UGIDLIMIT -F: '($3>=LIMIT) && ($3!=65534)' /root/ispc-migr/files/passwd > /root/ispc-migr/files/passwd.mig
  awk -v LIMIT=$UGIDLIMIT -F: '($3>=LIMIT) && ($3!=65534)' /root/ispc-migr/files/group > /root/ispc-migr/files/group.mig
  awk -v LIMIT=$UGIDLIMIT -F: '($3>=LIMIT) && ($3!=65534) {print $1}' /root/ispc-migr/files/passwd | tee - |egrep -f - /root/ispc-migr/files/shadow > /root/ispc-migr/files/shadow.mig
  echo ""
  echo "###############################################################"
  echo "✓ User migration files prepared successfully!"
  echo "###############################################################"
  echo ""
  echo "Files saved to: /root/ispc-migr/files/"
  echo "  - passwd.mig (migrated users)"
  echo "  - group.mig (migrated groups)"
  echo "  - shadow.mig (password hashes)"
  echo ""
  echo "NEXT STEP: Run menu option (7) to import these users/groups."
  echo ""
      pause_before_menu
}

function import_users {
    clear
  echo "###############################################################"
  echo "###############################################################"
  echo "##        Import Users, Groups & System Accounts             ##"
  echo "###############################################################"
  echo "##  This will:                                               ##"
  echo "##    1. Check for UID/GID conflicts                         ##"
  echo "##    2. Display users/groups to be imported                 ##"
  echo "##    3. Create backups of current system files              ##"
  echo "##    4. Import all migrated users and groups                ##"
  echo "##    5. Run integrity checks                                ##"
  echo "###############################################################"
  echo ""
  
  # Check if migration files exist
  if [[ ! -f /root/ispc-migr/files/passwd.mig ]]; then
    echo "ERROR: passwd.mig not found. Run option (6) first to export users."
        pause_before_menu
    return
  fi
  
  echo "Checking for UID/GID conflicts with existing users..."
  echo ""
  
  # Extract UIDs from migration file and check for conflicts
  CONFLICTS=0
  declare -a CONFLICT_LINES
  while IFS=: read -r username password uid gid gecos home shell; do
    if id -u "$username" &>/dev/null 2>&1; then
      EXISTING_UID=$(id -u "$username" 2>/dev/null)
      if [[ "$EXISTING_UID" != "$uid" ]]; then
        CONFLICT_LINES+=("CONFLICT: User '$username' exists with UID $EXISTING_UID but migration has UID $uid")
        ((CONFLICTS++))
      fi
    fi
    if grep -q "^[^:]*:[^:]*:$uid:" /etc/passwd 2>/dev/null; then
      CONFLICT_USER=$(awk -F: -v UID="$uid" '$3==UID {print $1; exit}' /etc/passwd)
      if [[ "$CONFLICT_USER" != "$username" ]]; then
        CONFLICT_LINES+=("CONFLICT: UID $uid already exists (user: $CONFLICT_USER) but migration wants user '$username' with same UID")
        ((CONFLICTS++))
      fi
    fi
  done < /root/ispc-migr/files/passwd.mig
  
  # Display conflicts if any
  if [[ $CONFLICTS -gt 0 ]]; then
    echo "⚠ Found $CONFLICTS conflict(s):"
    echo ""
    for line in "${CONFLICT_LINES[@]}"; do
      echo "  $line"
    done
    echo ""
    echo "Review the conflicts above. You may proceed anyway, but be aware of potential issues."
    echo ""
  else
    echo "✓ No conflicts detected."
    echo ""
  fi
  
  echo "###############################################################"
  echo "NEW ENTRIES TO BE ADDED:"
  echo "###############################################################"
  echo ""
  echo "Passwd entries:"
  cat /root/ispc-migr/files/passwd.mig
  echo ""
  echo "Group entries:"
  cat /root/ispc-migr/files/group.mig
  echo ""
  echo "Shadow entries:"
  cat /root/ispc-migr/files/shadow.mig
  echo ""
  if [[ -f /root/ispc-migr/files/gshadow.mig ]]; then
    echo "Gshadow entries:"
    cat /root/ispc-migr/files/gshadow.mig
    echo ""
  fi
  
  echo "###############################################################"
  read -p "Add these new entries to the system? (y/n): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Cancelled. No changes made."
    echo ""
        pause_before_menu
    return
  fi
  
  echo ""
  echo "###############################################################"
  echo "Creating backups before making changes..."
  echo "###############################################################"
  BACKUP_TIMESTAMP=$(date +%s)
  cp /etc/passwd /etc/passwd.backup.$BACKUP_TIMESTAMP
  cp /etc/group /etc/group.backup.$BACKUP_TIMESTAMP
  cp /etc/shadow /etc/shadow.backup.$BACKUP_TIMESTAMP
  cp /etc/gshadow /etc/gshadow.backup.$BACKUP_TIMESTAMP
  echo "✓ Backups created:"
  echo "  - /etc/passwd.backup.$BACKUP_TIMESTAMP"
  echo "  - /etc/group.backup.$BACKUP_TIMESTAMP"
  echo "  - /etc/shadow.backup.$BACKUP_TIMESTAMP"
  echo "  - /etc/gshadow.backup.$BACKUP_TIMESTAMP"
  echo ""
  
  echo "Importing passwd entries..."
  cat /root/ispc-migr/files/passwd.mig >> /etc/passwd
  echo "✓ Passwd entries added"
  
  echo "Importing group entries..."
  cat /root/ispc-migr/files/group.mig >> /etc/group
  echo "✓ Group entries added"
  
  echo "Importing shadow entries..."
  cat /root/ispc-migr/files/shadow.mig >> /etc/shadow
  echo "✓ Shadow entries added"
  
  if [[ -f /root/ispc-migr/files/gshadow.mig ]]; then
    echo "Importing gshadow entries..."
    cat /root/ispc-migr/files/gshadow.mig >> /etc/gshadow
    echo "✓ Gshadow entries added"
  fi
  
  echo ""
  echo "###############################################################"
  echo "Running integrity checks..."
  echo "###############################################################"
  echo ""
  
  # Check passwd integrity
  if ! pwck -r 2>&1 | head -20; then
    echo "⚠ WARNING: pwck found issues (see above). Consider manual review."
  else
    echo "✓ passwd file integrity OK"
  fi
  
  echo ""
  
  # Check group integrity
  if ! grpck -r 2>&1 | head -20; then
    echo "⚠ WARNING: grpck found issues (see above). Consider manual review."
  else
    echo "✓ group file integrity OK"
  fi
  
  echo ""
  echo "###############################################################"
  echo "Import complete!"
  echo "###############################################################"
  echo "IMPORTANT NOTES:"
  echo "- New user/group entries have been appended successfully"
  echo "- Backups saved with timestamp: $BACKUP_TIMESTAMP"
  echo "- To rollback: cp /etc/passwd.backup.$BACKUP_TIMESTAMP /etc/passwd (same for group/shadow/gshadow)"
  echo "- Test login for a migrated user to verify password hashes work"
  echo "- If issues occur, restore from backups immediately"
  echo "###############################################################"
  echo ""
      pause_before_menu
}

function mailman_migration {
    clear
  echo "###############################################################"
  echo "###############################################################"
  echo "############       Mailman migration              #############"
  echo "###############################################################"
  rsync $common_args $main_server:/var/lib/mailman/lists /var/lib/mailman
  rsync $common_args $main_server:/var/lib/mailman/data /var/lib/mailman
  rsync $common_args $main_server:/var/lib/mailman/archives /var/lib/mailman
  cd /var/lib/mailman/bin && ./genaliases
  echo "###############################################################"
  echo "###############################################################"
      pause_before_menu
}

function acme_migration {
  clear
  echo "###############################################################"
  echo "###############################################################"
  echo "############ ACME.sh Certificate Synchronization  #############"
  echo "###############################################################"
  echo ""
  echo "Syncing ACME.sh account data and certificates..."
  echo "Source: $main_server:/root/.acme.sh/"
  echo "Target: /root/.acme.sh/"
  echo ""
  rsync $common_args $main_server:/root/.acme.sh/ /root/.acme.sh
  echo ""
  echo "✓ ACME Migration completed successfully!"
  echo ""
  echo "Your ACME account credentials and certificates are now synced."
  echo "###############################################################"
  echo "###############################################################"
    pause_before_menu
}

function delete_ssh_key {
    clear
    echo "###############################################################"
    echo "##             Delete SSH Key from Remote Server             ##"
    echo "###############################################################"
    echo ""
    echo "This will remove your SSH public key from the remote server's"
    echo "authorized_keys file, requiring password authentication again."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    echo ""
    
    if [[ "$confirm" != "yes" ]]; then
        echo "Operation cancelled."
        echo ""
        pause_before_menu
        return
    fi
    
    SSH_KEY="$HOME/.ssh/id_rsa"
    
    if [[ ! -f "$SSH_KEY.pub" ]]; then
        echo "❌ ERROR: SSH public key not found at $SSH_KEY.pub"
        echo ""
        pause_before_menu
        return
    fi
    
    # Get the key fingerprint for identification
    KEY_FINGERPRINT=$(ssh-keygen -l -f "$SSH_KEY.pub" 2>/dev/null | awk '{print $2}')
    
    echo "Connecting to remote server to delete SSH key..."
    echo "Remote server: root@$main_server"
    echo "Key fingerprint: $KEY_FINGERPRINT"
    echo ""
    
    # Create a temp file with the public key
    TEMP_KEY=$(mktemp)
    cat "$SSH_KEY.pub" > "$TEMP_KEY"
    
    # Get the key content (first part before comment)
    KEY_CONTENT=$(cat "$SSH_KEY.pub" | awk '{print $1" "$2}')
    
    # Remove the key from authorized_keys
    DELETE_OUTPUT=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o BatchMode=yes "root@$main_server" "grep -v '$KEY_CONTENT' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>&1)
    DELETE_RESULT=$?
    
    rm -f "$TEMP_KEY"
    
    if [ $DELETE_RESULT -eq 0 ]; then
        echo "✅ SSH key successfully removed from remote server"
        echo ""
        echo "Password authentication has been re-enabled."
        echo "Next time you'll need to provide your password to connect."
        echo ""
    else
        echo "❌ Failed to remove SSH key from remote server"
        echo "Debug info: $DELETE_OUTPUT"
        echo ""
        echo "This may indicate:"
        echo "  1. SSH key is not currently installed on the server"
        echo "  2. Connection to remote server failed"
        echo "  3. Insufficient permissions"
        echo ""
    fi
    
    pause_before_menu
}

function exit {
        clear
        exit
}
menu
while [ "$input" != "0" ]
do
case "$input" in
    0) exit
    ;;
    1) install
    ;;
    2) change_hostname
    ;;
    3) update_server
    ;;
    4) install_ispconfig
    ;;
    5) reboot_server
    ;;
    6) db_migration
    ;;
    7) update_ispconfig_password
    ;;
    8) www_migration
    ;;
    9) mail_migration
    ;;
    a) files_migration
    ;;
    b) import_users
    ;;
    c) acme_migration
    ;;
    d) delete_ssh_key
    ;;
esac
done
clear