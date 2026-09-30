#!/usr/bin/env bash

BLUE='\033[0;34m'
NC='\033[0m'
GREEN='\033[1;32m'
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

echo "
  _____           _                       _____          _
 |  __ \         | |                     / ____|        | |
 | |__) |   ___  | |_   _ __    ___     | (___     ___  | |_   _   _   _ __
 |  _  /   / _ \ | __| | '__|  / _ \     \___ \   / _ \ | __| | | | | | '_ \
 | | \ \  |  __/ | |_  | |    | (_) |    ____) | |  __/ | |_  | |_| | | |_) |
 |_|  \_\  \___|  \__| |_|     \___/    |_____/   \___|  \__|  \__,_| | .__/
                                                                      | |
                                                                      |_|

                                                                  - CrYsTAxiT
"


apks="apks" && mkdir -p "$apks"
counter=1
#Status check function
check_adb_device(){
    adb get-state
}

#Factory Reset Function
factory_reset(){
    
    adb reboot bootloader
    
    sleep 10
    
    fastboot devices
    read -rp "Are you sure you want to wipe data (Y/n): " option_1
    
    if [ "$option_1" = "Y" ]; then
        
        echo "Wiping userdata and cache partition..."
        fastboot -w
        
    fi
    
    sleep 3
    
    fastboot reboot
    
    
}


enable_connectivity(){
    adb shell cmd connectivity airplane-mode enable
    
    adb shell cmd -w wifi set-wifi-enabled enabled
    
    adb shell cmd bluetooth_manager enable

    echo "Network config applied:"
    echo "[✓] Airplane mode enabled"
    echo "[✓] Wi-Fi enabled"
    echo "[✓] Bluetooth enabled"
}

get_files(){
    curl -sfL -o "${apks}\RetroArch.apk" https://buildbot.libretro.com/stable/1.22.2/android/RetroArch.apk
    
    curl -sfL -o "${apks}\ppsspp.apk" https://www.ppsspp.org/files/1_20_4/ppsspp.apk
    
    curl -sfL -o "${apks}\daijishou.apk" https://github.com/TapiocaFox/Daijishou/releases/download/v1.5.0/416.apk
    
    echo -e "${GREEN} Downloading apks completed..."
    
    sleep 5
}

install_files(){
    echo "Installing apks..."
    
    adb install -g RetroArch.apk
    echo "Installed RetroArch"
    
    adb install -g ppsspp.apk
    echo "Installed ppsspp"

    adb install -g daijishou.apk
    echo "Installed Daijishou"
    sleep 2
    echo -e "${GREEN} Installation completed..."
    
}



main_menu(){
    while true; do
        echo -e "\n"
        echo -e "${BOLD}Select an option:${NORMAL} "
        
        echo -e "${BLUE}1)${NC} Check device connection"
        echo -e "${BLUE}2)${NC} Factory reset device"
        echo -e "${BLUE}3)${NC} Remove bloatware / preinstalled apps"
        echo -e "${BLUE}4)${NC} Download retro gaming apps"
        echo -e "${BLUE}5)${NC} Install retro gaming apps"
        echo -e "${BLUE}6)${NC} Enable airplane mode + WiFi & Bluetooth"
        echo -e "${BLUE}7)${NC} Run full setup (1 to 6 in order)"
        echo -e "${BLUE}8)${NC} Show status"
        echo -e "${BLUE}0)${NC} Exit"
        
        echo -e "\n"
        
        read -erp "${BOLD}Choice [0-7]:${NORMAL} " option
        
        #Menu functions
        case "$option" in
            1)
            check_adb_device ;;
            
            2)
            factory_reset ;;
            
            3)
            ;;
            4)
            get_files ;;
            5)
            install_files ;;
            6)
            enable_connectivity ;;
            7)
              while true; do
                check_adb_device
                factory_reset
                remove_bloatware
                get_files
                install_files
                enable_connectivity

                ((counter++))

                if [ $counter -gt 7 ]; then
                  break
                fi
              done

              echo -e "${GREEN} Installation completed!!"
            ;;
            8)
            ;;
            0)exit;;
        esac
        
    done
    
}

main_menu