# Common functions and variables for erofs-helper

# Define color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
BOLD="\033[1m"
RESET="\033[0m"

# Global variables for cleanup
MOUNT_DIR=""
RAW_IMAGE=""
TEMP_ROOT=""
OUTPUT_IMG_TMP=""
MOUNT_POINT=""

# Banner function
print_banner() {
  echo -e "${BOLD}${GREEN}"
  echo "╔═════════════════════════════════════════════════════════════════╗"
  echo "║  EROFS Helper Script - by @deuxielll forked from @ravindu644    ║"
  echo "╚═════════════════════════════════════════════════════════════════╝"
  echo -e "${RESET}"
}

check_dependencies() {
    # Check for Windows
    if [[ "$(uname -s)" == *"_NT"* ]]; then
        echo -e "${YELLOW}Windows detected.${RESET}"
        echo -e "${BLUE}This script is designed for Linux-based environments.${RESET}"
        echo -e "For Windows, it's recommended to use Windows Subsystem for Linux (WSL)."
        echo -e "Please install WSL and run this script from within the WSL terminal."
        echo -e "For more information on WSL: https://learn.microsoft.com/en-us/windows/wsl/install"
        exit 1
    fi

    local missing_deps=0
    local missing_cmds=()
    # Check for libtoolize as a proxy for libtool
    local deps=("make" "automake" "libtoolize" "git" "fusermount3" "uuidgen" "mkfs.erofs" "mkfs.ext4" "simg2img" "tar" "sha256sum" "numfmt" "stat" "awk" "sed" "grep" "find" "chown" "chmod" "mount" "umount" "e2fsck" "dd" "pkg-config" "aclocal")

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps=$((missing_deps + 1))
            missing_cmds+=("$cmd")
        fi
    done
    
    if [ "$missing_deps" -gt 0 ]; then
        echo -e "${BLUE}Checking for required tools...${RESET}"
        declare -A dep_map
        dep_map=(
            ["make"]="make"
            ["automake"]="automake"
            ["libtoolize"]="libtool"
            ["git"]="git"
            ["fusermount3"]="fuse3"
            ["uuidgen"]="uuid-runtime"
            ["mkfs.erofs"]="erofs-utils"
            ["mkfs.ext4"]="e2fsprogs"
            ["simg2img"]="android-sdk-libsparse-utils"
            ["tar"]="tar"
            ["sha256sum"]="coreutils"
            ["numfmt"]="coreutils"
            ["stat"]="coreutils"
            ["awk"]="gawk"
            ["sed"]="sed"
            ["grep"]="grep"
            ["find"]="findutils"
            ["chown"]="coreutils"
            ["chmod"]="coreutils"
            ["mount"]="util-linux"
            ["umount"]="util-linux"
            ["e2fsck"]="e2fsprogs"
            ["dd"]="coreutils"
            ["pkg-config"]="pkg-config"
            ["aclocal"]="automake"
        )
        
        local missing_pkg=()
        local install_erofs_from_source=false
        for cmd in "${missing_cmds[@]}"; do
            echo -e "${RED}[✗] Command not found: ${BOLD}$cmd${RESET}"
            if [ "$cmd" == "mkfs.erofs" ]; then
                install_erofs_from_source=true
            else
                pkg=${dep_map[$cmd]}
                if [[ ! " ${missing_pkg[@]} " =~ " ${pkg} " ]]; then
                    missing_pkg+=("$pkg")
                fi
            fi
        done

        # If building erofs-utils from source, ensure uuid-dev is installed
        if $install_erofs_from_source; then
            if [[ ! " ${missing_pkg[@]} " =~ " uuid-dev " ]]; then
                missing_pkg+=("uuid-dev")
            fi
            if [[ ! " ${missing_pkg[@]} " =~ " liblz4-dev " ]]; then
                missing_pkg+=("liblz4-dev")
            fi
            if [[ ! " ${missing_pkg[@]} " =~ " zlib1g-dev " ]]; then
                missing_pkg+=("zlib1g-dev")
            fi
        fi

        # Show found dependencies only when some are missing
        for cmd in "${deps[@]}"; do
            if ! [[ " ${missing_cmds[@]} " =~ " ${cmd} " ]]; then
                 echo -e "${GREEN}[✓] Found: ${BOLD}$cmd${RESET}"
            fi
        done

        echo -e "\n${RED}Error: ${missing_deps} required tool(s) are missing.${RESET}"
        if $install_erofs_from_source; then
            echo -e "${YELLOW}The 'mkfs.erofs' command is missing and will be built from source.${RESET}"
        fi
        if [ ${#missing_pkg[@]} -gt 0 ]; then
            echo -e "${YELLOW}The following packages seem to be missing or incomplete:${RESET}"
            echo -e "${BOLD}${missing_pkg[*]}${RESET}"
        fi
        
        read -p "Do you want to try and install them now? (y/N) " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            if command -v apt &> /dev/null; then
                if [ ${#missing_pkg[@]} -gt 0 ]; then
                    sudo apt update
                    sudo apt install -y "${missing_pkg[@]}"
                fi

                if $install_erofs_from_source; then
                    echo -e "\n${BLUE}Building and installing erofs-utils from source...${RESET}"
                    if [ -d "$HOME/erofs-utils" ]; then
                        echo -e "${YELLOW}Existing erofs-utils directory found. Removing it...${RESET}"
                        rm -rf "$HOME/erofs-utils"
                    fi
                    cd ~
                    git clone https://github.com/erofs/erofs-utils.git
                    cd erofs-utils
                    mkdir -p m4
                    ./autogen.sh
                    ./configure --enable-fuse --enable-multithreading --with-lz4
                    make
                    sudo make install
                    cd ..
                fi

                echo -e "\n${GREEN}Dependencies installed. Please run the script again.${RESET}"
                exit 0
            else
                echo -e "\n${RED}Error: 'apt' package manager not found. Please install the packages manually.${RESET}"
                exit 1
            fi
        else
            echo -e "${YELLOW}Installation aborted. Please install the missing dependencies and try again.${RESET}"
            exit 1
        fi
    fi
}

cleanup() {
    echo -e "\n${YELLOW}Cleaning up temporary files...${RESET}"

    # Unmount any mounted filesystems
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        umount "$MOUNT_DIR" 2>/dev/null || umount -l "$MOUNT_DIR" 2>/dev/null
    fi
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        sync
        umount "$MOUNT_POINT" 2>/dev/null || umount -l "$MOUNT_POINT" 2>/dev/null
    fi
    
    # Remove temporary files and directories
    [ -n "$RAW_IMAGE" ] && [ -f "$RAW_IMAGE" ] && rm -f "$RAW_IMAGE"
    [ -d "$MOUNT_DIR" ] && rm -rf "$MOUNT_DIR"
    [ -d "$TEMP_ROOT" ] && rm -rf "$TEMP_ROOT"
    [ -f "$OUTPUT_IMG_TMP" ] && rm -f "$OUTPUT_IMG_TMP"
    
    echo -e "${GREEN}Cleanup completed.${RESET}"
    # Only exit with error if called from trap
    [ "$1" = "ERROR" ] && exit 1 || exit 0
}

clean_all() {
    tput cnorm # Restore cursor in case it's hidden
    clear
    echo -e "${RED}${BOLD}DANGER: This will permanently delete the contents of the following directories:${RESET}"
    echo -e "- ./original_images"
    echo -e "- ./extracted_images"
    echo -e "- ./repacked_images"
    read -p "Are you sure you want to continue? (y/N) " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deleting contents...${RESET}"
        if [ -d "./original_images" ]; then
            find ./original_images -mindepth 1 -delete
        fi
        if [ -d "./extracted_images" ]; then
            find ./extracted_images -mindepth 1 -delete
        fi
        if [ -d "./repacked_images" ]; then
            find ./repacked_images -mindepth 1 -delete
        fi
        
        echo -e "${YELLOW}Recreating directories...${RESET}"
        mkdir -p ./original_images ./extracted_images ./repacked_images
        
        echo -e "${GREEN}All clean.${RESET}"
    else
        echo -e "${YELLOW}Operation cancelled.${RESET}"
    fi
}

show_progress() {
    local current=$1
    local total=$2
    local message=$3
    local bar_width=40

    if [ "$total" -eq 0 ]; then total=1; fi # Avoid division by zero
    local percentage=$((current * 100 / total))
    if [ "$percentage" -gt 100 ]; then percentage=100; fi

    local filled_width=$((percentage * bar_width / 100))
    local empty_width=$((bar_width - filled_width))
    
    local progress_bar=""
    for ((i=0; i<filled_width; i++)); do
        progress_bar+="▓"
    done
    for ((i=0; i<empty_width; i++)); do
        progress_bar+="░"
    done

    echo -ne "\r\033[K${BLUE}$message: [${progress_bar}] ${percentage}% (${current}/${total})${RESET}"
}

show_copy_progress() {
    local pid=$1
    local src_dir=$2
    local dst_dir=$3
    local message=$4
    local total_size
    total_size=$(du -sb "$src_dir" | cut -f1)
    
    local bar_width=40

    # Hide cursor
    tput civis
    # Clear screen and move cursor to top-left
    clear
    tput cup 0 0

    while kill -0 "$pid" 2>/dev/null; do
        current_size=$(du -sb "$dst_dir" 2>/dev/null | cut -f1)
        if [ -z "$current_size" ]; then current_size=0; fi

        if [ "$total_size" -gt 0 ]; then
            percentage=$((current_size * 100 / total_size))
        else
            percentage=0
        fi
        if [ "$percentage" -gt 100 ]; then percentage=100; fi

        # Progress bar calculation
        filled_width=$((percentage * bar_width / 100))
        empty_width=$((bar_width - filled_width))
        
        progress_bar=""
        for ((i=0; i<filled_width; i++)); do
            progress_bar+="▓"
        done
        for ((i=0; i<empty_width; i++)); do
            progress_bar+="░"
        done

        current_hr=$(numfmt --to=iec-i --suffix=B "$current_size")
        total_hr=$(numfmt --to=iec-i --suffix=B "$total_size")
        
        # Move cursor to top-left and print updated progress
        tput cup 0 0
        echo -e "${BLUE}$message: [${progress_bar}] ${percentage}% (${current_hr}/${total_hr})${RESET}"
        sleep 0.1
    done
    
    # Final 100% display
    full_bar=""
    for ((i=0; i<bar_width; i++)); do
        full_bar+="▓"
    done
    total_hr=$(numfmt --to=iec-i --suffix=B "$total_size")
    tput cup 0 0
    echo -e "${GREEN}$message: [${full_bar}] 100% (${total_hr}/${total_hr})${RESET}"
    
    # Show cursor
    tput cnorm
    echo ""
}

# Interactive menu function
# Usage: create_menu "selected_index" "Menu Title" "Option 1" "Option 2" ...
create_menu() {
    local selected_index=$1
    local title=$2
    shift 2
    local options=("$@")
    
    # Move cursor to a specific line and clear from there downwards
    tput cup 5 0
    tput ed
    tput civis # Hide cursor
    
    echo -e "${BLUE}${BOLD}$title${RESET}\n"
    
    for i in "${!options[@]}"; do
        if [ "$i" -eq "$selected_index" ]; then
            echo -e "${GREEN} > ${options[$i]}${RESET}"
        else
            echo -e "   ${options[$i]}"
        fi
    done
}
