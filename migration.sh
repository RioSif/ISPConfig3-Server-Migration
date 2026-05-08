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
www_start="service nginx start"
www_stop="service nginx stop"
db_start="service mysql start"
db_stop="service mysql stop"

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
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$main_server" "echo Test connection successful" 2>/dev/null; then
        echo "✓ SSH key authentication is working!"
        echo ""
    else
        echo "⚠ SSH key connection failed. Attempting to copy key to remote server..."
        echo "Please enter the root password for the remote server:"
        read -s ssh_setup_password
        echo $ssh_setup_password
        
        if [[ -z "$ssh_setup_password" ]]; then
            echo "Password empty. Skipping SSH key copy."
            echo "You can copy it manually later:"
            cat "$SSH_KEY.pub"
            echo ""
        else
            # Use sshpass if available, otherwise try direct ssh-copy-id
            if command -v sshpass >/dev/null 2>&1; then
                echo "Using sshpass to copy key..."
                SSHPASS="$ssh_setup_password" sshpass -e ssh-copy-id -i "$SSH_KEY.pub" -o StrictHostKeyChecking=accept-new "root@$main_server" 2>/dev/null
            else
                # Try direct approach with ssh-copy-id
                echo "Trying direct approach with ssh-copy-id"
                ssh-copy-id -i "$SSH_KEY.pub" -o StrictHostKeyChecking=accept-new "root@$main_server" 2>/dev/null || {
                    echo "ssh-copy-id failed. Installing sshpass and retrying..."
                    apt-get update && apt-get install -y sshpass
                    SSHPASS="$ssh_setup_password" sshpass -e ssh-copy-id -i "$SSH_KEY.pub" -o StrictHostKeyChecking=accept-new "root@$main_server" 2>/dev/null
                }
            fi
            echo "✓ SSH public key copied to remote server"
            echo ""
            
            # Test again after copying
            if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$main_server" "echo Test connection successful" 2>/dev/null; then
                echo "✓ SSH key authentication is now working!"
                echo ""
            fi
        fi
        
        unset ssh_setup_password
    fi
}

echo "Please enter the IP address of your master (remote) server:"
read main_server
echo ""

setup_ssh_keys

function menu {
    clear
    echo "###############################################################"
    echo "##                    Main menu                              ##"
    echo "##                                                           ##"
    echo "## Install RSync on the remote server                  (1)   ##"
    echo "## Synchronize MySql                                   (2)   ##"
    echo "## Update ISPConfig MySQL Password                     (3)   ##"
    echo "## Synchronize websites                                (4)   ##"
    echo "## Synchronize email                                   (5)   ##"
    echo "## Synchronize passwords, users and other files        (6)   ##"
    echo "## Import users & passwords (run after option 6)       (7)   ##"
    echo "## Synchronize LetsEncrypt                             (8)   ##"
	  echo "## Synchronize Acme                                    (9)   ##"
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
    echo "Installing RSync on the remote server..."
    ssh $main_server "$install_rsync"
    echo "Installation complete"
      pause_before_menu
}

function db_migration {
  clear
  
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
  echo "############## Start MySql Migration              #############"
  echo "############## Step1:                             #############"
  echo "############## Back up the remote databases       #############"
  echo "###############################################################"
  echo "############## Step2:                             #############"
  echo "############## Copy the backed-up databases       #############"
  echo "###############################################################"
  echo "############## Step3:                             #############"
  echo "############## Import the databases into MySql    #############"
  echo "###############################################################"
  echo "###############################################################"
  echo " "
  echo "Back up the remote databases............................................................."
  ssh $main_server "mkdir -p /root/ispc-migr/mysql; MYSQL_PWD='$remote_mysql_root_password' mysqldump -u root --force --all-databases > /root/ispc-migr/mysql/fulldump.sql"
  clear
  echo "Copy the backup.........................................................................."
  rsync $common_args $main_server:/root/ispc-migr /root
  clear
  echo "Import the backup........................................................................"
  MYSQL_PWD='$local_mysql_root_password' mysql -u root < /root/ispc-migr/mysql/fulldump.sql
  clear
  echo "Upgrade mysql system tables if target server has newer mysql/mariadb versions..........................................................."
  MYSQL_PWD='$local_mysql_root_password' mysql_upgrade -uroot --force
  #
  # mysql_upgrade also does:
  ## mysqlcheck --all-databases --check-upgrade --auto-repair
  ## mysql < fix_priv_tables
  #
  # Therefore, no need to run again mysqlcheck with autorepair below
  ##echo "Check and repair the databases..........................................................."
  ##mysqlcheck -p -A --auto-repair
  echo "###############################################################"
  echo "###############################################################"
  pause_before_menu
}

function update_ispconfig_password {
    clear
    echo "###############################################################"
    echo "###############################################################"
    echo "############ Update ISPConfig MySQL Password    #############"
    echo "###############################################################"
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
            echo "Password: $first_char$masked$last_three"
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
    echo "###############################################################"
    echo ""
    
    unset new_ispconfig_password
    pause_before_menu
}

function www_migration {
    clear

  echo "###############################################################"
  echo "###############################################################"
  echo "################## Web Migration             ##################"
  echo "################## Step1:                    ##################"
  echo "################## Stop the webserver        ##################"
  echo "###############################################################"
  echo "################## Step2:                    ##################"
  echo "################## Start the migration       ##################"
  echo "###############################################################"
  echo "################## Step3:                    ##################"
  echo "################## Start the webserver       ##################"
  echo "###############################################################"
  $www_stop
  rsync $common_args $main_server:/var/www/ /var/www
  rsync $common_args $main_server:/var/log/ispconfig/httpd/ /var/log/ispconfig/httpd
  rsync $common_args --exclude='acme.vhost' --exclude='apps.vhost' --exclude='default' --exclude='ispconfig.vhost' $main_server:/etc/nginx/sites-available/ /etc/nginx/sites-available
  rsync $common_args --exclude='000-apps.vhost' --exclude='000-ispconfig.vhost' --exclude='999-acme.vhost' --exclude='default' $main_server:/etc/nginx/sites-enabled/ /etc/nginx/sites-enabled
  rsync $common_args $main_server:/etc/nginx/custom /etc/nginx
  rsync $common_args $main_server:/etc/nginx/services /etc/nginx
  $www_start
  echo "###############################################################"
  echo "###############################################################"
      pause_before_menu
}

function mail_migration {
    clear
  echo "###############################################################"
  echo "###############################################################"
  echo "################## Mail Migration            ##################"
  echo "################## Step1:                    ##################"
  echo "################## Migrate vmail             ##################"
  echo "###############################################################"
  echo "################## Step2:                    ##################"
  echo "################## Migrate vmail logs        ##################"
  echo "###############################################################"
  rsync $common_args $main_server:/var/vmail/ /var/vmail
  rsync $common_args $main_server:/var/log/mail.* /var/log/
  echo "###############################################################"
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
  echo "############# Import users+passwords (option 9 in menu) #######"
  echo "###############################################################"
  echo "###############################################################"
  mkdir -p /root/ispc-migr/files
  rsync $common_args $main_server:/var/backup/ /var/backup
  rsync $common_args $main_server:/etc/passwd /root/ispc-migr/files/
  rsync $common_args $main_server:/etc/group  /root/ispc-migr/files/
  rsync $common_args $main_server:/etc/shadow  /root/ispc-migr/files/
  rsync $common_args $main_server:/etc/gshadow  /root/ispc-migr/files/
  echo "###############################################################"
  echo "###############################################################"
  echo "## exporting passwd, group, shadow and gshadow files ##"
  awk -v LIMIT=$UGIDLIMIT -F: '($3>=LIMIT) && ($3!=65534)' /root/ispc-migr/files/passwd > /root/ispc-migr/files/passwd.mig
  awk -v LIMIT=$UGIDLIMIT -F: '($3>=LIMIT) && ($3!=65534)' /root/ispc-migr/files/group > /root/ispc-migr/files/group.mig
  awk -v LIMIT=$UGIDLIMIT -F: '($3>=LIMIT) && ($3!=65534) {print $1}' /root/ispc-migr/files/passwd | tee - |egrep -f - /root/ispc-migr/files/shadow > /root/ispc-migr/files/shadow.mig
  echo ""
  echo "User migration files prepared. Run menu option (9) to import them."
  echo ""
      pause_before_menu
}

function import_users {
    clear
  echo "###############################################################"
  echo "###############################################################"
  echo "############# IMPORT USERS & PASSWORDS               #########"
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
  echo "############ Mailman migration                 #############"
  echo "###############################################################"
  rsync $common_args $main_server:/var/lib/mailman/lists /var/lib/mailman
  rsync $common_args $main_server:/var/lib/mailman/data /var/lib/mailman
  rsync $common_args $main_server:/var/lib/mailman/archives /var/lib/mailman
  cd /var/lib/mailman/bin && ./genaliases
  echo "###############################################################"
  echo "###############################################################"
      pause_before_menu
}
function le_migration {
    clear
  echo "###############################################################"
  echo "###############################################################"
  echo "############ LetsEncrypt migration                #############"
  echo "###############################################################"
  rsync $common_args $main_server:/etc/letsencrypt /etc
  echo "###############################################################"
  echo "###############################################################"
      pause_before_menu
}
function acme_migration {
  echo "Starting ACME Migration..."
  rsync $common_args $main_server:/root/.acme.sh/ /root/.acme.sh
  echo "ACME Migration done."
  echo "###############################################################"
  echo "###############################################################"
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
    2) db_migration
    ;;
    3) update_ispconfig_password
    ;;
    4) www_migration
    ;;
    5) mail_migration
    ;;
    6) files_migration
    ;;
    7) import_users
    ;;
    8) le_migration
    ;;
	9) acme_migration
	;;
esac    
done