#!/bin/bash

# Removed set -e to handle errors gracefully

# Parse command line arguments
SAVE_TO_FILE=false
while [[ $# -gt 0 ]]; do
  case $1 in
    -f|--file)
      SAVE_TO_FILE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -f, --file    Save output to file (default: display only)"
      echo "  -h, --help    Show this help message"
      echo ""
      echo "Example:"
      echo "  $0           # Display audit on screen only"
      echo "  $0 --file    # Save audit to timestamped file"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use -h or --help for usage information"
      exit 1
      ;;
  esac
done

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
HOSTNAME=$(scutil --get ComputerName 2>/dev/null || hostname)
ARCH=$(uname -m)

# Get script directory and create reports folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$(dirname "$SCRIPT_DIR")/reports"
OUTPUT="$REPORTS_DIR/mac_audit_${HOSTNAME}_${TIMESTAMP}.txt"

# Only redirect to file if --file flag is used
if [ "$SAVE_TO_FILE" = true ]; then
  # Create reports directory if it doesn't exist
  mkdir -p "$REPORTS_DIR"
  exec > >(tee "$OUTPUT") 2>&1
fi

section() {
  echo
  echo "================================================"
  echo "$1"
  echo "================================================"
}

echo "macOS SYSTEM AUDIT"
echo "Generated : $(date)"
echo "Hostname  : $HOSTNAME"
echo "Arch      : $ARCH"
if [ "$SAVE_TO_FILE" = true ]; then
  echo "Output    : $OUTPUT"
else
  echo "Output    : Display only (use --file to save)"
fi

# ------------------------------------------------
section "SYSTEM INFO"

# Get OS version info
os_version=$(sw_vers -productVersion)
os_build=$(sw_vers -buildVersion)
os_major=$(echo "$os_version" | cut -d. -f1)

# Map macOS version to marketing name
# Note: Apple doesn't provide this dynamically, so we maintain this lookup table
# Update when new macOS versions are released
declare -A os_names=(
  [26]="Tahoe"        # Released Sept 2025
  [15]="Sequoia"      # Released 2024
  [14]="Sonoma"       # Released 2023
  [13]="Ventura"      # Released 2022
  [12]="Monterey"     # Released 2021
  [11]="Big Sur"      # Released 2020
  [10]="Catalina"     # macOS 10.15 (2019)
)

# Get the friendly name
if [[ "$os_major" == "10" ]]; then
  # Handle macOS 10.x versions
  os_minor=$(echo "$os_version" | cut -d. -f2)
  case $os_minor in
    15) os_name="Catalina" ;;
    14) os_name="Mojave" ;;
    13) os_name="High Sierra" ;;
    12) os_name="Sierra" ;;
    *) os_name="macOS 10.$os_minor" ;;
  esac
else
  # macOS 11+ uses single major version numbers
  os_name="${os_names[$os_major]}"
  if [ -z "$os_name" ]; then
    # Future version not in our map yet
    os_name="macOS $os_major"
  fi
fi

echo "OS Name: macOS $os_name"
echo "Version: $os_version"
echo "Build: $os_build"
echo "Kernel: $(uname -r)"
echo "Architecture: $ARCH"

# ------------------------------------------------
section "HARDWARE"
system_profiler SPHardwareDataType | grep -E "Model Name|Model Identifier|Chip|Total Number of Cores|Memory|Serial Number" | sed 's/^[[:space:]]*//'

# ------------------------------------------------
section "DEVICE USAGE"

# Get serial number for reference
serial_number=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $NF}')

echo "Serial Number: $serial_number"
echo "Warranty Check: https://checkcoverage.apple.com"
echo

# macOS installation and setup dates
if [ -f /var/db/.AppleSetupDone ]; then
  # Birth time = when current macOS was first installed
  first_install=$(stat -f "%SB" /var/db/.AppleSetupDone 2>/dev/null)
  first_install_epoch=$(stat -f "%B" /var/db/.AppleSetupDone 2>/dev/null)
  
  # Modification time = last setup completion (could be same or after reset)
  last_setup=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" /var/db/.AppleSetupDone 2>/dev/null)
  last_setup_epoch=$(stat -f "%m" /var/db/.AppleSetupDone 2>/dev/null)
  
  current_epoch=$(date +%s)
  
  if [ ! -z "$first_install" ]; then
    echo "Current macOS Installed: $first_install"
    days_since_install=$(( ($current_epoch - $first_install_epoch) / 86400 ))
    years_since_install=$(echo "scale=1; $days_since_install / 365" | bc)
    echo "Time Since Install: $days_since_install days (~$years_since_install years)"
  fi
  
  if [ ! -z "$last_setup" ] && [ "$first_install_epoch" != "$last_setup_epoch" ]; then
    echo
    echo "Last Setup Completed: $last_setup"
    days_since_setup=$(( ($current_epoch - $last_setup_epoch) / 86400 ))
    echo "Days Since Setup: $days_since_setup days"
  else
    days_since_setup=$days_since_install
  fi
fi

echo
# Current uptime
echo "Current Uptime:"
uptime_output=$(uptime)
echo "  $uptime_output"

# Last boot time
boot_date=$(who -b | awk '{print $3, $4}')
if [ -z "$boot_date" ]; then
  boot_date=$(sysctl -n kern.boottime | awk '{print $5, $6, $7, $8, $9}')
fi
echo "  Last Boot: $boot_date"

echo
# Recent reboot history
echo "Recent Reboots (Last 10):"
last reboot | head -10 | awk '{if (NF > 0) print "  " $0}'

echo
# Calculate average uptime pattern
# Count both reboot and shutdown events
total_events=$(last reboot | wc -l | tr -d ' ')
reboot_count=$(last reboot | grep -c "^reboot" || echo "0")
shutdown_count=$(last reboot | grep -c "^shutdown" || echo "0")

# Use days_since_setup if available, otherwise days_since_install
days_for_calc="${days_since_setup:-$days_since_install}"

if [ "$total_events" -gt 1 ] && [ ! -z "$days_for_calc" ]; then
  echo "Total Reboot/Shutdown Events: $total_events (Reboots: $reboot_count, Shutdowns: $shutdown_count)"
  
  # Calculate average days between events (using total events)
  if [ "$total_events" -gt 0 ]; then
    avg_days_between=$(awk "BEGIN {printf \"%.1f\", $days_for_calc / $total_events}")
    echo "Average Days Between Reboots/Shutdowns: ~$avg_days_between days"
    
    # Usage pattern assessment
    avg_int=$(echo "$avg_days_between" | cut -d. -f1)
    if [ "$avg_int" -gt 30 ]; then
      echo "Usage Pattern: ⚠ Infrequent reboots (consider restarting more often for updates)"
    elif [ "$avg_int" -gt 7 ]; then
      echo "Usage Pattern: ✓ Moderate usage (healthy reboot frequency)"
    else
      echo "Usage Pattern: ℹ Frequent reboots (may indicate stability issues or testing)"
    fi
  fi
fi

# ------------------------------------------------
section "CPU & LOAD"
uptime
top -l 1 | grep -E "^CPU usage"
echo
load_avg=$(uptime | awk -F'load averages: ' '{print $2}' | awk '{print $1}' | tr -d ',')
load_check=$(echo "$load_avg < $(sysctl -n hw.ncpu)" | bc)
if [ "$load_check" -eq 1 ]; then
  echo "Status: ✓ Healthy (Load < CPU cores)"
else
  echo "Status: ⚠ High Load (Load >= CPU cores)"
fi
echo "Reference: Healthy when load average < number of CPU cores"

# ------------------------------------------------
section "MEMORY"
TOTAL_RAM=$(sysctl -n hw.memsize)
echo "Total RAM: $(echo "$TOTAL_RAM / 1073741824" | bc)GB"
echo

# Get vm_stat output and calculate human-readable values
PAGE_SIZE=16384
vm_output=$(vm_stat)

pages_free=$(echo "$vm_output" | grep "Pages free" | awk '{print $3}' | tr -d '.')
pages_active=$(echo "$vm_output" | grep "Pages active" | awk '{print $3}' | tr -d '.')
pages_inactive=$(echo "$vm_output" | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
pages_wired=$(echo "$vm_output" | grep "Pages wired down" | awk '{print $4}' | tr -d '.')

# Convert to GB (pages * 16384 / 1024^3)
free_gb=$(echo "scale=2; $pages_free * $PAGE_SIZE / 1073741824" | bc)
active_gb=$(echo "scale=2; $pages_active * $PAGE_SIZE / 1073741824" | bc)
inactive_gb=$(echo "scale=2; $pages_inactive * $PAGE_SIZE / 1073741824" | bc)
wired_gb=$(echo "scale=2; $pages_wired * $PAGE_SIZE / 1073741824" | bc)
used_gb=$(echo "scale=2; ($pages_active + $pages_inactive + $pages_wired) * $PAGE_SIZE / 1073741824" | bc)

echo "Memory Usage:"
echo "  Active:   ${active_gb}GB"
echo "  Inactive: ${inactive_gb}GB"
echo "  Wired:    ${wired_gb}GB"
echo "  Free:     ${free_gb}GB"
echo "  Used:     ${used_gb}GB"
echo
# Memory pressure check
mem_pressure=$(echo "scale=2; $used_gb / $(echo "$TOTAL_RAM / 1073741824" | bc) * 100" | bc | cut -d'.' -f1)
if [ "$mem_pressure" -lt 80 ]; then
  echo "Status: ✓ Healthy (${mem_pressure}% used)"
elif [ "$mem_pressure" -lt 90 ]; then
  echo "Status: ⚠ Moderate (${mem_pressure}% used)"
else
  echo "Status: ✗ Critical (${mem_pressure}% used)"
fi
echo "Reference: Healthy < 80%, Warning 80-90%, Critical > 90%"

# ------------------------------------------------
section "STORAGE"
df -h | grep -E "^/dev/disk|^Filesystem" | head -n 5
echo

# Check Data volume (where user data is stored) - typically /System/Volumes/Data
data_volume=$(df -h | grep "/System/Volumes/Data" | head -1)
if [ ! -z "$data_volume" ]; then
  data_used=$(echo "$data_volume" | awk '{print $5}' | tr -d '%')
  data_avail=$(echo "$data_volume" | awk '{print $4}')
  data_total=$(echo "$data_volume" | awk '{print $2}')
  
  echo "Primary Storage (Data Volume):"
  echo "  Total: $data_total"
  echo "  Available: $data_avail"
  echo "  Usage: ${data_used}%"
  echo
  
  if [ "$data_used" -lt 80 ]; then
    echo "Status: ✓ Healthy (${data_used}% used)"
  elif [ "$data_used" -lt 90 ]; then
    echo "Status: ⚠ Moderate (${data_used}% used)"
  elif [ "$data_used" -lt 95 ]; then
    echo "Status: ⚠ High (${data_used}% used)"
  else
    echo "Status: ✗ Critical (${data_used}% used)"
  fi
else
  # Fallback to root volume if Data volume not found
  main_disk_usage=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
  main_avail=$(df -h / | tail -1 | awk '{print $4}')
  
  echo "Main Disk Available: $main_avail"
  echo
  
  if [ "$main_disk_usage" -lt 80 ]; then
    echo "Status: ✓ Healthy (${main_disk_usage}% used)"
  elif [ "$main_disk_usage" -lt 90 ]; then
    echo "Status: ⚠ Moderate (${main_disk_usage}% used)"
  else
    echo "Status: ✗ Critical (${main_disk_usage}% used)"
  fi
fi

echo "Reference: Healthy < 80%, Warning 80-90%, High 90-95%, Critical > 95%"
echo "           Keep at least 10-20GB free for optimal performance"

# ------------------------------------------------
section "BATTERY" 
battery_info=$(system_profiler SPPowerDataType | grep -E "Cycle Count|Condition|Maximum Capacity|State of Charge" | sed 's/^[[:space:]]*//')
echo "$battery_info"
echo
# Battery health check
cycle_count=$(echo "$battery_info" | grep "Cycle Count" | awk -F': ' '{print $2}')
max_capacity=$(echo "$battery_info" | grep "Maximum Capacity" | awk -F': ' '{print $2}' | tr -d '%')
condition=$(echo "$battery_info" | grep "Condition" | awk -F': ' '{print $2}')

if [ "$condition" = "Normal" ] && [ "$max_capacity" -ge 80 ]; then
  echo "Status: ✓ Healthy (${max_capacity}%, ${cycle_count} cycles)"
elif [ "$max_capacity" -ge 70 ]; then
  echo "Status: ⚠ Fair (${max_capacity}%, ${cycle_count} cycles)"
else
  echo "Status: ✗ Replace Soon (${max_capacity}%, ${cycle_count} cycles)"
fi
echo "Reference: Apple recommends service when capacity ≤ 80%"
echo "           Modern MacBooks (2016+) rated for 1,000 cycles"
echo "           Designed to retain 80% capacity at max cycle count"

# ------------------------------------------------
section "SECURITY"

# System Integrity Protection (SIP)
echo "System Integrity Protection (SIP):"
sip_status=$(csrutil status 2>/dev/null | grep -q "enabled" && echo "enabled" || echo "disabled")
echo "  Status: $sip_status"
if [ "$sip_status" = "enabled" ]; then
  echo "  ✓ Check: Enabled"
else
  echo "  ✗ Check: Disabled"
fi

echo
# FileVault
echo "FileVault (Full Disk Encryption):"
fv_status=$(fdesetup status 2>/dev/null)
if echo "$fv_status" | grep -q "FileVault is On"; then
  echo "  Status: On"
  fv_users=$(fdesetup list 2>/dev/null | wc -l)
  echo "  Users with access: $fv_users"
  echo "  ✓ Check: Enabled"
else
  echo "  Status: Off"
  echo "  ✗ Check: Disabled"
fi

echo
# Firewall
echo "Firewall:"
fw_state=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)
stealth_mode=$(defaults read /Library/Preferences/com.apple.alf stealthenabled 2>/dev/null)
if [ "$fw_state" = "1" ] || [ "$fw_state" = "2" ]; then
  echo "  Status: Enabled"
  echo "  ✓ Check: Enabled"
  if [ "$stealth_mode" = "1" ]; then
    echo "  Stealth Mode: On"
    echo "  ✓ Check: Stealth mode enabled"
  else
    echo "  Stealth Mode: Off"
    echo "  ✗ Check: Stealth mode disabled"
  fi
elif [ "$fw_state" = "0" ]; then
  echo "  Status: Disabled"
  echo "  ✗ Check: Disabled"
else
  echo "  Status: Unknown"
  echo "  ✗ Check: Unknown"
fi

echo
# Gatekeeper
echo "Gatekeeper (App Security):"
gk_status=$(spctl --status 2>/dev/null)
echo "  Status: $gk_status"
gk_assess=$(spctl --assess --verbose /Applications/Safari.app 2>&1 | grep -o "accepted\|rejected" | head -1)
echo "  Policy: $(defaults read /var/db/SystemPolicy-prefs.plist enabled 2>/dev/null | grep -q "yes" && echo "Enforced" || echo "Not enforced")"
if echo "$gk_status" | grep -q "enabled"; then
  echo "  ✓ Check: Enabled"
else
  echo "  ✗ Check: Disabled"
fi

echo
# Automatic Updates
echo "Software Updates:"
auto_check=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null || echo "0")
auto_download=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload 2>/dev/null || echo "0")
auto_install=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates 2>/dev/null || echo "0")
[ -z "$auto_check" ] && auto_check="0"
[ -z "$auto_download" ] && auto_download="0"
[ -z "$auto_install" ] && auto_install="0"
echo "  Auto Check: $([ "$auto_check" = "1" ] && echo "On" || echo "Off")"
echo "  Auto Download: $([ "$auto_download" = "1" ] && echo "On" || echo "Off")"
echo "  Auto Install: $([ "$auto_install" = "1" ] && echo "On" || echo "Off")"
if [ "$auto_check" = "1" ]; then
  echo "  ✓ Check: Automatic updates enabled"
else
  echo "  ✗ Check: Automatic updates disabled"
fi

echo
# Screen Lock / Password Requirements
echo "Screen Lock Settings:"
screen_saver_delay=$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null || echo "Not set")
ask_for_password=$(defaults read com.apple.screensaver askForPassword 2>/dev/null || echo "0")
password_delay=$(defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null || echo "0")

# Check if Apple Silicon (which has different/better security defaults)
if [ "$ARCH" = "arm64" ]; then
  echo "  Architecture: Apple Silicon (Built-in security)"
  echo "  Screen Lock: Always required after sleep/wake"
  echo "  ✓ Check: Screen lock password required (Apple Silicon default)"
  screen_lock_secure=true
else
  echo "  Screen Saver Delay: ${screen_saver_delay}s"
  echo "  Require Password: $([ "$ask_for_password" = "1" ] && echo "Yes" || echo "No")"
  if [ "$ask_for_password" = "1" ]; then
    echo "  Password Delay: ${password_delay}s"
    echo "  ✓ Check: Screen lock password required"
    screen_lock_secure=true
  else
    echo "  ✗ Check: Screen lock password not required"
    screen_lock_secure=false
  fi
fi

echo
# Admin Accounts
echo "User Accounts:"
admin_count=$(dscl . -read /Groups/admin GroupMembership 2>/dev/null | wc -w)
admin_count=$((admin_count - 1)) # subtract "GroupMembership:" label
echo "  Admin accounts: $admin_count"
echo "  Current user: $(whoami)"
current_user_admin=$(groups $(whoami) | grep -q "admin" && echo "Yes (Admin)" || echo "No (Standard)")
echo "  Current user type: $current_user_admin"

echo
# Automatic Login
echo "Automatic Login:"
auto_login=$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null)
if [ -z "$auto_login" ]; then
  echo "  Status: Disabled"
  echo "  ✓ Check: Automatic login disabled"
else
  echo "  Status: Enabled (User: $auto_login)"
  echo "  ✗ Check: Automatic login enabled"
fi

echo
# MDM Enrollment (for personal Mac, should be none or minimal)
echo "Mobile Device Management (MDM):"
mdm_enrolled=$(profiles status -type enrollment 2>/dev/null)

# Check if enrolled via DEP
if echo "$mdm_enrolled" | grep -q "Enrolled via DEP: Yes"; then
  echo "  Status: ⚠ Supervised/DEP Enrolled (Organization-managed)"
  echo "  Warning: Personal Macs should not be DEP/supervised enrolled"
  dep_enrolled=true
else
  dep_enrolled=false
fi

# Check if MDM enrolled
if echo "$mdm_enrolled" | grep -q "MDM enrollment: Yes"; then
  echo "  Status: ⚠ MDM Enrolled (Organization-managed)"
  echo "  Warning: Personal Macs typically should not be MDM enrolled"
  mdm_active=true
else
  mdm_active=false
fi

# Check for configuration profiles
profile_count=$(profiles list 2>/dev/null | grep -c "attribute: name:") || profile_count="0"
if [ "$profile_count" -gt 0 ]; then
  echo "  Profiles: $profile_count configuration profile(s) installed"
  profiles list 2>/dev/null | grep "attribute: name:" | sed 's/.*: /    - /' | head -5
fi

# If no DEP, no MDM, and no profiles - it's a clean personal Mac
if [ "$dep_enrolled" = false ] && [ "$mdm_active" = false ] && [ "$profile_count" -eq 0 ]; then
  echo "  Status: ✓ Not enrolled (Clean Personal Mac)"
fi

echo
# Overall Security Health Assessment
security_score=0
max_score=8

echo "─────────────────────────────────────────────"

# Check 1: SIP
[ "$sip_status" = "enabled" ] && ((security_score++)) || true

# Check 2: FileVault
echo "$fv_status" | grep -q "FileVault is On" && ((security_score++)) || true

# Check 3: Firewall
[ "$fw_state" = "1" ] || [ "$fw_state" = "2" ] && ((security_score++)) || true

# Check 4: Stealth Mode
[ "$stealth_mode" = "1" ] && ((security_score++)) || true

# Check 5: Gatekeeper
echo "$gk_status" | grep -q "enabled" && ((security_score++)) || true

# Check 6: Automatic Updates
[ "$auto_check" = "1" ] && ((security_score++)) || true

# Check 7: Screen Lock Password
[ "$screen_lock_secure" = true ] && ((security_score++)) || true

# Check 8: Automatic Login
[ -z "$auto_login" ] && ((security_score++)) || true

if [ "$security_score" -ge 7 ]; then
  echo "Overall Status: ✓ Excellent Security ($security_score/$max_score checks passed)"
elif [ "$security_score" -ge 5 ]; then
  echo "Overall Status: ⚠ Good Security ($security_score/$max_score checks passed)"
elif [ "$security_score" -ge 3 ]; then
  echo "Overall Status: ⚠ Fair Security ($security_score/$max_score checks passed)"
else
  echo "Overall Status: ✗ Poor Security ($security_score/$max_score checks passed)"
fi

# ------------------------------------------------
section "NETWORK"
echo "IP Address:"
ifconfig en0 | grep "inet " | awk '{print "  " $2}'
echo
echo "Status:"
net_status=$(ifconfig en0 | grep "status:" | awk '{print $2}')
echo "  $net_status"
echo
echo "Connected Network:"
system_profiler SPAirPortDataType | grep -A 5 "Current Network Information:" | grep -E "PHY Mode:|Channel:|Security:|Signal / Noise:" | head -n 4
echo
# Network health check
signal_strength=$(system_profiler SPAirPortDataType | grep "Signal / Noise:" | head -1 | awk -F': ' '{print $2}' | awk '{print $1}' | tr -d 'dBm')
if [ ! -z "$signal_strength" ]; then
  if [ "$signal_strength" -gt -50 ]; then
    echo "Status: ✓ Excellent signal (${signal_strength} dBm)"
  elif [ "$signal_strength" -gt -60 ]; then
    echo "Status: ✓ Good signal (${signal_strength} dBm)"
  elif [ "$signal_strength" -gt -70 ]; then
    echo "Status: ⚠ Fair signal (${signal_strength} dBm)"
  else
    echo "Status: ✗ Weak signal (${signal_strength} dBm)"
  fi
  echo "Reference: -30 dBm = Excellent, -50 dBm = Good, -60 dBm = Fair"
  echo "           -70 dBm = Weak, -80 dBm = Very weak, -90 dBm = Unusable"
else
  if [ "$net_status" = "active" ]; then
    echo "Status: ✓ Connected (Wired)"
  else
    echo "Status: ✗ Disconnected"
  fi
fi

echo
echo "================================================"
echo "AUDIT COMPLETE"
if [ "$SAVE_TO_FILE" = true ]; then
  echo "Report saved to: $OUTPUT"
fi
echo "================================================"
