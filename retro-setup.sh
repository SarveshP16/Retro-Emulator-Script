#!/usr/bin/env bash
#
# Retro Emulator setup
# Turns an old Android phone into a dedicated retro gaming handheld.
#
# Requires: adb, fastboot, curl (and a device with USB debugging enabled).

set -o pipefail

BLUE='\033[0;34m'
NC='\033[0m'
GREEN='\033[1;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
if [ -t 1 ] && tput bold >/dev/null 2>&1; then
    BOLD=$(tput bold)
    NORMAL=$(tput sgr0)
else
    BOLD=''
    NORMAL=''
fi

echo "
  _____           _                       _____          _
 |  __ \         | |                     / ____|        | |
 | |__) |   ___  | |_   _ __    ___     | (___     ___  | |_   _   _   _ __
 |  _  /   / _ \ | __| | '__|  / _ \     \___ \   / _ \ | __| | | | | | '_ \\
 | | \ \  |  __/ | |_  | |    | (_) |    ____) | |  __/ | |_  | |_| | | |_) |
 |_|  \_\  \___|  \__| |_|     \___/    |_____/   \___|  \__|  \__,_| | .__/
                                                                      | |
                                                                      |_|

                                                                  - CrYsTAxiT
"


apks="apks" && mkdir -p "$apks"

# Pinned app versions
RETROARCH_VERSION="1.22.2"
PPSSPP_VERSION="1_20_4"
DAIJISHOU_VERSION="v1.5.0"

# Packages the setup installs, used by the status report
PKG_RETROARCH_32="com.retroarch"
PKG_RETROARCH_64="com.retroarch.aarch64"
PKG_PPSSPP="org.ppsspp.ppsspp"
PKG_DAIJISHOU="com.magneticchen.daijishou"

# Bloatware removed with "pm uninstall --user 0": the package is dropped for
# the current user but its APK stays on /system, so a factory reset or
# "cmd package install-existing <pkg>" brings it back.
bloatware=(
    # Google
    com.google.android.apps.docs
    com.google.android.apps.maps
    com.google.android.apps.photos
    com.google.android.apps.tachyon
    com.google.android.apps.youtube.music
    com.google.android.gm
    com.google.android.music
    com.google.android.videos
    com.google.android.youtube
    # Facebook / Meta preloads
    com.facebook.appmanager
    com.facebook.katana
    com.facebook.services
    com.facebook.system
    com.instagram.android
    # Other third-party preloads
    com.amazon.appmanager
    com.amazon.mShop.android.shopping
    com.linkedin.android
    com.microsoft.office.outlook
    com.microsoft.skydrive
    com.netflix.mediaclient
    com.netflix.partner.activation
    com.spotify.music
    # Samsung
    com.samsung.android.app.spage
    com.samsung.android.bixby.agent
    com.samsung.android.game.gamehome
    com.samsung.android.scloud
    com.samsung.android.visionintelligence
    # Xiaomi / MIUI
    com.mi.android.globalFileexplorer
    com.mi.globalbrowser
    com.miui.analytics
    com.miui.player
    com.miui.videoplayer
    com.xiaomi.glgm
    com.xiaomi.mipicks
    # Oppo / Realme / Vivo
    com.coloros.gamespace
    com.heytap.cloud
    com.heytap.music
    com.oppo.market
    com.vivo.appstore
    com.vivo.browser
)

info() { echo -e "${BLUE}[*]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }

#Dependency check
require_tools(){
    local missing=()
    local tool
    for tool in "$@"; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        err "Missing required tool(s): ${missing[*]}"
        err "Install the Android platform-tools and make sure they are on your PATH."
        return 1
    fi
}

#Status check function
check_adb_device(){
    require_tools adb || return 1

    local state
    state=$(adb get-state 2>&1)

    if [ "$state" = "device" ]; then
        local manufacturer model
        manufacturer=$(adb shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r')
        model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')

        ok "Device connected and authorised"
        echo "    Manufacturer: ${manufacturer:-unknown}"
        echo "    Model:        ${model:-unknown}"
        return 0
    fi

    case "$state" in
        *unauthorized*)
            err "Device is unauthorised — accept the USB debugging prompt on the phone." ;;
        *"no devices"*|*"not found"*|*"device offline"*)
            err "No device detected — enable USB debugging and reconnect the cable." ;;
        *)
            err "Device not ready: $state" ;;
    esac
    return 1
}

#Wait for the device to come back after a reboot
wait_for_device(){
    info "Waiting for the device to come back online..."

    if adb wait-for-device; then
        ok "Device is online"
        return 0
    fi

    err "Timed out waiting for the device"
    return 1
}

#Factory Reset Function
factory_reset(){
    require_tools adb fastboot || return 1

    warn "A factory reset erases ALL user data on the device."
    read -rp "Reboot into the bootloader and continue? (y/N): " confirm_reboot

    case "$confirm_reboot" in
        [yY]|[yY][eE][sS]) ;;
        *) info "Factory reset cancelled"; return 0 ;;
    esac

    info "Rebooting into bootloader..."
    adb reboot bootloader || { err "Could not reboot into the bootloader"; return 1; }

    sleep 10

    if ! fastboot devices | grep -q .; then
        err "No fastboot device found — the bootloader may still be locked."
        return 1
    fi
    fastboot devices

    read -rp "Are you sure you want to wipe data (y/N): " option_1

    case "$option_1" in
        [yY]|[yY][eE][sS])

            echo "Wiping userdata and cache partition..."
            if fastboot -w; then
                ok "Userdata and cache wiped"
            else
                err "Wipe failed — is the bootloader unlocked?"
            fi
            ;;
        *)
            info "Wipe skipped"
            ;;
    esac

    sleep 3

    info "Rebooting the device..."
    fastboot reboot

    wait_for_device
}

#Bloatware removal
remove_bloatware(){
    check_adb_device || return 1

    info "Scanning for preinstalled apps that can be removed..."

    local present installed=() pkg
    present=$(adb shell pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://')

    for pkg in "${bloatware[@]}"; do
        if grep -qx "$pkg" <<< "$present"; then
            installed+=("$pkg")
        fi
    done

    if [ ${#installed[@]} -eq 0 ]; then
        ok "No known bloatware found on this device"
        return 0
    fi

    echo
    echo "${BOLD}The following ${#installed[@]} package(s) will be removed for the current user:${NORMAL}"
    printf '    %s\n' "${installed[@]}"
    echo
    warn "Apps are uninstalled for user 0 only — a factory reset restores them."
    read -rp "Proceed? (y/N): " confirm

    case "$confirm" in
        [yY]|[yY][eE][sS]) ;;
        *) info "Bloatware removal cancelled"; return 0 ;;
    esac

    local removed=0 skipped=0
    for pkg in "${installed[@]}"; do
        if adb shell pm uninstall -k --user 0 "$pkg" 2>/dev/null | tr -d '\r' | grep -q Success; then
            ok "Removed $pkg"
            removed=$((removed + 1))
        else
            warn "Could not remove $pkg (protected system app)"
            skipped=$((skipped + 1))
        fi
    done

    echo
    echo -e "${GREEN}Bloatware removal finished: $removed removed, $skipped skipped${NC}"
}

#Pick the RetroArch build matching the device CPU
retroarch_apk_name(){
    local abi=""

    if [ "$(adb get-state 2>/dev/null)" = "device" ]; then
        abi=$(adb shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
    fi

    case "$abi" in
        armeabi*|x86) echo "RetroArch.apk" ;;
        *)            echo "RetroArch_aarch64.apk" ;;
    esac
}

#Download a single file and check that something actually arrived
download(){
    local url="$1" dest="$2" name="$3"

    info "Downloading $name..."

    if ! curl -fL --retry 3 --progress-bar -o "$dest" "$url"; then
        err "Failed to download $name from $url"
        rm -f "$dest"
        return 1
    fi

    if [ ! -s "$dest" ]; then
        err "$name downloaded as an empty file"
        rm -f "$dest"
        return 1
    fi

    ok "$name saved to $dest"
}

get_files(){
    require_tools curl || return 1

    local retroarch_apk failures=0
    retroarch_apk=$(retroarch_apk_name)

    download \
        "https://buildbot.libretro.com/stable/${RETROARCH_VERSION}/android/${retroarch_apk}" \
        "${apks}/RetroArch.apk" \
        "RetroArch ${RETROARCH_VERSION} (${retroarch_apk})" || failures=$((failures + 1))

    download \
        "https://www.ppsspp.org/files/${PPSSPP_VERSION}/ppsspp.apk" \
        "${apks}/ppsspp.apk" \
        "PPSSPP ${PPSSPP_VERSION}" || failures=$((failures + 1))

    download \
        "https://github.com/TapiocaFox/Daijishou/releases/download/${DAIJISHOU_VERSION}/416.apk" \
        "${apks}/daijishou.apk" \
        "Daijishou ${DAIJISHOU_VERSION}" || failures=$((failures + 1))

    echo
    if [ "$failures" -gt 0 ]; then
        err "$failures download(s) failed"
        return 1
    fi

    echo -e "${GREEN}Downloading apks completed...${NC}"
}

install_files(){
    check_adb_device || return 1

    local apk found=0 installed=0 failures=0

    echo "Installing apks..."

    for apk in "${apks}"/*.apk; do
        [ -e "$apk" ] || continue
        found=1

        info "Installing $(basename "$apk")..."
        if adb install -r -g "$apk"; then
            ok "Installed $(basename "$apk")"
            installed=$((installed + 1))
        else
            err "Failed to install $(basename "$apk")"
            failures=$((failures + 1))
        fi
    done

    if [ "$found" -eq 0 ]; then
        err "No apks found in ./${apks} — run option 4 first."
        return 1
    fi

    sleep 2

    echo
    if [ "$failures" -gt 0 ]; then
        err "Installation finished with $failures failure(s), $installed installed"
        return 1
    fi

    echo -e "${GREEN}Installation completed: $installed app(s)${NC}"
}

enable_connectivity(){
    check_adb_device || return 1

    # Airplane mode cuts every radio first; Wi-Fi and Bluetooth then go back on
    # so the handheld keeps downloads and controllers but no mobile data.
    adb shell cmd connectivity airplane-mode enable >/dev/null 2>&1

    sleep 2

    adb shell cmd -w wifi set-wifi-enabled enabled >/dev/null 2>&1

    adb shell cmd bluetooth_manager enable >/dev/null 2>&1

    echo "Network config applied:"
    echo "[✓] Airplane mode enabled"
    echo "[✓] Wi-Fi enabled"
    echo "[✓] Bluetooth enabled"
}

#Status report
show_status(){
    local apk found=0

    echo
    echo "${BOLD}=== Local files ===${NORMAL}"
    for apk in "${apks}"/*.apk; do
        [ -e "$apk" ] || continue
        found=1
        printf '    %-20s %s\n' "$(basename "$apk")" "$(du -h "$apk" | cut -f1)"
    done
    [ "$found" -eq 0 ] && warn "No apks downloaded yet (option 4)"

    echo
    echo "${BOLD}=== Device ===${NORMAL}"
    check_adb_device || return 1

    local android_version sdk abi battery storage
    android_version=$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    sdk=$(adb shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')
    abi=$(adb shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
    echo "    Android:      ${android_version:-unknown} (API ${sdk:-?})"
    echo "    CPU ABI:      ${abi:-unknown}"

    battery=$(adb shell dumpsys battery 2>/dev/null | tr -d '\r' | awk '/level:/ {print $2; exit}')
    [ -n "$battery" ] && echo "    Battery:      ${battery}%"

    storage=$(adb shell df -h /data 2>/dev/null | tr -d '\r' | awk 'NR==2 {print $4" free of "$2}')
    [ -n "$storage" ] && echo "    Storage:      $storage"

    local present
    present=$(adb shell pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://')

    pkg_status(){
        local label="$1" pkg="$2"

        if grep -qx "$pkg" <<< "$present"; then
            ok "$label ($pkg)"
        else
            warn "$label not installed"
        fi
    }

    echo
    echo "${BOLD}=== Emulator apps ===${NORMAL}"
    if grep -qx "$PKG_RETROARCH_64" <<< "$present"; then
        pkg_status "RetroArch" "$PKG_RETROARCH_64"
    else
        pkg_status "RetroArch" "$PKG_RETROARCH_32"
    fi
    pkg_status "PPSSPP"    "$PKG_PPSSPP"
    pkg_status "Daijishou" "$PKG_DAIJISHOU"

    echo
    echo "${BOLD}=== Connectivity ===${NORMAL}"
    local airplane wifi bt
    airplane=$(adb shell settings get global airplane_mode_on 2>/dev/null | tr -d '\r')
    wifi=$(adb shell settings get global wifi_on 2>/dev/null | tr -d '\r')
    bt=$(adb shell settings get global bluetooth_on 2>/dev/null | tr -d '\r')
    if [ "$airplane" = "1" ]; then ok "Airplane mode enabled"; else warn "Airplane mode disabled"; fi
    if [ "$wifi" = "1" ];     then ok "Wi-Fi enabled";          else warn "Wi-Fi disabled"; fi
    if [ "$bt" = "1" ];       then ok "Bluetooth enabled";      else warn "Bluetooth disabled"; fi

    local bloat_left=0 pkg
    for pkg in "${bloatware[@]}"; do
        grep -qx "$pkg" <<< "$present" && bloat_left=$((bloat_left + 1))
    done

    echo
    echo "${BOLD}=== Bloatware ===${NORMAL}"
    if [ "$bloat_left" -eq 0 ]; then
        ok "No known bloatware remaining"
    else
        warn "$bloat_left known package(s) still installed (option 3)"
    fi
}

#Run every step in order, stopping at the first failure
full_setup(){
    local step

    for step in check_adb_device factory_reset remove_bloatware get_files install_files enable_connectivity; do
        echo
        echo -e "${BOLD}--- ${step//_/ } ---${NORMAL}"

        if ! "$step"; then
            err "Step '${step//_/ }' failed — stopping full setup."
            return 1
        fi
    done

    echo
    echo -e "${GREEN}Installation completed!!${NC}"
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

        read -erp "${BOLD}Choice [0-8]:${NORMAL} " option || exit 0

        #Menu functions
        case "$option" in
            1)
            check_adb_device ;;

            2)
            factory_reset ;;

            3)
            remove_bloatware ;;

            4)
            get_files ;;

            5)
            install_files ;;

            6)
            enable_connectivity ;;

            7)
            full_setup ;;

            8)
            show_status ;;

            0)
            echo "Bye!" && exit 0 ;;

            "")
            ;;

            *)
            err "Invalid choice: $option" ;;
        esac

    done

}

main_menu
