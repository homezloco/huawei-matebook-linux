#!/usr/bin/env bash
# =============================================================================
# huawei-thermal — Thermal management and fan control for Huawei MateBook
# Tested on: MateBook X Pro 2024 (VGHH-XX)
# =============================================================================

set -euo pipefail

# --- Colours -----------------------------------------------------------------
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

# --- Helpers -----------------------------------------------------------------
info()  { echo -e "${BLU}•${RST} $*"; }
ok()    { echo -e "${GRN}✓${RST} $*"; }
warn()  { echo -e "${YLW}!${RST} $*"; }
err()   { echo -e "${RED}✗${RST} $*" >&2; }
die()   { err "$*"; exit 1; }
hdr()   { echo -e "\n${BLD}${CYN}$*${RST}"; }

need_root() {
    [[ $EUID -eq 0 ]] || die "This command requires root. Run with sudo."
}

# --- Thermal Zones -----------------------------------------------------------
_get_thermal_zones() {
    ls -d /sys/class/thermal/thermal_zone* 2>/dev/null || true
}

_get_cooling_devices() {
    ls -d /sys/class/thermal/cooling_device* 2>/dev/null || true
}

# --- Fan Control (via ACPI or pwm) ------------------------------------------
_fan_path() {
    # Common fan paths
    local paths=(
        "/sys/class/hwmon/hwmon*/pwm1"
        "/sys/class/thermal/cooling_device*/cur_state"
        "/proc/acpi/ibm/fan"
        "/sys/devices/platform/huawei/fan_speed"
    )
    for p in "${paths[@]}"; do
        if ls $p 2>/dev/null | head -1; then return 0; fi
    done
    return 1
}

# =============================================================================
# STATUS — Current thermal state
# =============================================================================
cmd_status() {
    hdr "Thermal Status"
    
    # CPU temperature
    local cpu_temp="N/A"
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        local temp_raw
        temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp)
        cpu_temp=$((temp_raw / 1000))
        local color="$GRN"
        [[ $cpu_temp -gt 70 ]] && color="$YLW"
        [[ $cpu_temp -gt 85 ]] && color="$RED"
        echo -e "  CPU Temperature: ${color}${cpu_temp}°C${RST}"
    else
        warn "  CPU temperature sensor not found"
    fi
    
    # All thermal zones
    hdr "Thermal Zones"
    local zones
    zones=$(_get_thermal_zones)
    if [[ -n "$zones" ]]; then
        for zone in $zones; do
            local zone_name temp type
            zone_name=$(basename "$zone")
            type=$(cat "$zone/type" 2>/dev/null || echo "unknown")
            if [[ -f "$zone/temp" ]]; then
                temp=$(cat "$zone/temp")
                temp=$((temp / 1000))
                local color="$GRN"
                [[ $temp -gt 70 ]] && color="$YLW"
                [[ $temp -gt 85 ]] && color="$RED"
                printf "  %-20s %3s°C  (%s)\n" "$zone_name" "${color}${temp}${RST}" "$type"
            else
                printf "  %-20s (no temp data)\n" "$zone_name"
            fi
        done
    else
        warn "  No thermal zones found"
    fi
    
    # Cooling devices (fans)
    hdr "Cooling Devices"
    local cooling
    cooling=$(_get_cooling_devices)
    if [[ -n "$cooling" ]]; then
        for dev in $cooling; do
            local dev_name type cur max
            dev_name=$(basename "$dev")
            type=$(cat "$dev/type" 2>/dev/null || echo "unknown")
            cur=$(cat "$dev/cur_state" 2>/dev/null || echo "?")
            max=$(cat "$dev/max_state" 2>/dev/null || echo "?")
            printf "  %-20s state: %s/%s  (%s)\n" "$dev_name" "$cur" "$max" "$type"
        done
    else
        warn "  No cooling devices found"
    fi
    
    # Fan speed (if available)
    # Note: [[ -f /path/glob* ]] does NOT expand the glob — bash skips pathname
    # expansion inside [[ ]], so the old guard tested a literal '*' path, was
    # always false, and this never printed even with fan1_input present.
    # Resolve the glob into an array and test the first match instead.
    local fan_files=(/sys/class/hwmon/hwmon*/fan1_input)
    if [[ -f "${fan_files[0]}" ]]; then
        local fan_speed
        fan_speed=$(cat "${fan_files[0]}" 2>/dev/null || true)
        if [[ -n "$fan_speed" && "$fan_speed" != "0" ]]; then
            ok "  Fan speed: ${fan_speed} RPM"
        fi
    fi

    # Power consumption (if available) — same glob caveat as above
    local power_files=(/sys/class/power_supply/BAT*/power_now)
    if [[ -f "${power_files[0]}" ]]; then
        local power
        power=$(cat "${power_files[0]}" 2>/dev/null || true)
        if [[ -n "$power" ]]; then
            local watts=$((power / 1000000))
            echo -e "  Power draw: ${watts}W"
        fi
    fi
    
    echo ""
}

# =============================================================================
# FAN — Fan control commands
# =============================================================================
cmd_fan() {
    local sub="${1:-status}"
    shift 2>/dev/null || true
    
    case "$sub" in
        status)
            hdr "Fan Status"
            local fan_path
            fan_path=$(_fan_path)
            if [[ -n "$fan_path" ]]; then
                ok "Fan control available at: $fan_path"
                if [[ -f "$fan_path" ]]; then
                    local cur_val
                    cur_val=$(cat "$fan_path")
                    echo "  Current value: $cur_val"
                fi
            else
                warn "No direct fan control found"
                info "Attempting to detect via hwmon..."
                ls -la /sys/class/hwmon/hwmon*/ 2>/dev/null | grep -E "fan|pwm" || true
            fi
            ;;
            
        set)
            need_root
            local level="${1:-}"
            [[ -n "$level" ]] || die "Usage: huawei-thermal fan set <level>"
            
            # Try different fan control methods
            local fan_path
            fan_path=$(_fan_path)
            if [[ -n "$fan_path" ]]; then
                echo "$level" > "$fan_path" 2>/dev/null && \
                    ok "Fan level set to: $level" || \
                    warn "Failed to set fan level"
            else
                die "No fan control interface found"
            fi
            ;;
            
        auto)
            need_root
            # Set automatic fan control
            local fan_path
            fan_path=$(_fan_path)
            if [[ -n "$fan_path" ]]; then
                echo "0" > "$fan_path" 2>/dev/null && \
                    ok "Fan set to automatic control" || \
                    warn "Failed to enable auto mode"
            fi
            ;;
            
        *)
            err "Unknown fan subcommand: $sub"
            echo "Usage: huawei-thermal fan {status|set <level>|auto}"
            exit 1
            ;;
    esac
}

# =============================================================================
# PROFILE — Thermal/Power profiles
# =============================================================================
cmd_profile() {
    local sub="${1:-status}"
    shift 2>/dev/null || true
    
    # Check for platform_profile (ACPI)
    _get_profile() {
        if [[ -f /sys/firmware/acpi/platform_profile ]]; then
            cat /sys/firmware/acpi/platform_profile
        elif command -v powerprofilesctl &>/dev/null; then
            powerprofilesctl get 2>/dev/null
        else
            echo "unavailable"
        fi
    }
    
    _set_profile() {
        local profile="$1"
        if [[ -f /sys/firmware/acpi/platform_profile ]]; then
            need_root
            echo "$profile" > /sys/firmware/acpi/platform_profile && \
                ok "Platform profile set to: $profile"
        elif command -v powerprofilesctl &>/dev/null; then
            powerprofilesctl set "$profile" && \
                ok "Power profile set to: $profile"
        else
            die "No profile control mechanism available"
        fi
    }
    
    case "$sub" in
        status)
            hdr "Thermal Profile"
            local current
            current=$(_get_profile)
            echo -e "  Current profile: ${BLD}${current}${RST}"
            
            if [[ -f /sys/firmware/acpi/platform_profile_choices ]]; then
                local choices
                choices=$(cat /sys/firmware/acpi/platform_profile_choices)
                echo "  Available: $choices"
            fi
            ;;
            
        quiet|cool|low-power)
            _set_profile "low-power"
            ;;
            
        balanced)
            _set_profile "balanced"
            ;;
            
        performance|high)
            _set_profile "performance"
            ;;
            
        set)
            local profile="${1:-}"
            [[ -n "$profile" ]] || die "Usage: huawei-thermal profile set <balanced|performance|low-power>"
            _set_profile "$profile"
            ;;
            
        *)
            err "Unknown profile subcommand: $sub"
            echo "Usage: huawei-thermal profile {status|quiet|balanced|performance|set <profile>}"
            exit 1
            ;;
    esac
}

# =============================================================================
# MONITOR — Continuous thermal monitoring
# =============================================================================
cmd_monitor() {
    local interval="${1:-2}"
    
    hdr "Thermal Monitor (Ctrl+C to stop)"
    echo "  Refresh interval: ${interval}s"
    echo ""
    
    # Hide cursor
    tput civis 2>/dev/null || true
    
    # Cleanup on exit
    trap 'tput cnorm 2>/dev/null || true; echo -e "\n\nMonitor stopped"; exit 0' INT TERM EXIT
    
    while true; do
        # Move cursor up and clear lines
        tput cuu1 2>/dev/null || true
        tput el 2>/dev/null || true
        
        local cpu_temp="N/A"
        if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
            cpu_temp=$(cat /sys/class/thermal/thermal_zone0/temp)
            cpu_temp=$((cpu_temp / 1000))
        fi
        
        local color="$GRN"
        [[ $cpu_temp -gt 70 ]] && color="$YLW"
        [[ $cpu_temp -gt 85 ]] && color="$RED"
        
        printf "\r  CPU: ${color}%3s°C${RST} | %s" "$cpu_temp" "$(date '+%H:%M:%S')"
        
        sleep "$interval"
    done
}

# =============================================================================
# UNDERVOLT — CPU undervolting (requires intel-undervolt)
# =============================================================================
cmd_undervolt() {
    if ! command -v intel-undervolt &>/dev/null; then
        die "intel-undervolt not installed. Install with: sudo apt install intel-undervolt"
    fi
    
    local sub="${1:-status}"
    shift 2>/dev/null || true
    
    case "$sub" in
        status)
            hdr "CPU Undervolt Status"
            intel-undervolt read 2>/dev/null || warn "Could not read undervolt settings"
            ;;
            
        apply)
            need_root
            local offset="${1:--50}"
            intel-undervolt apply --core "$offset" --cache "$offset" && \
                ok "Undervolt applied: ${offset}mV" || \
                err "Failed to apply undervolt"
            ;;
            
        reset)
            need_root
            intel-undervolt apply --core 0 --cache 0 && \
                ok "Undervolt reset to 0mV"
            ;;
            
        *)
            err "Unknown undervolt subcommand: $sub"
            echo "Usage: huawei-thermal undervolt {status|apply [offset]|reset}"
            echo "  offset: negative value in mV (e.g., -50 for 50mV undervolt)"
            exit 1
            ;;
    esac
}

# =============================================================================
# THROTTLE — Check thermal throttling status
# =============================================================================
cmd_throttle() {
    hdr "Thermal Throttling Status"
    
    # Check MSR for thermal throttling (x86 only)
    if [[ -f /dev/cpu/0/msr ]]; then
        need_root
        local msr_val
        msr_val=$(rdmsr -p0 0x19c 2>/dev/null || echo "0")
        # Decode thermal status
        local thermal_status=$((msr_val & 0x1))
        local prochot=$(( (msr_val >> 1) & 0x1 ))
        local crit_temp=$(( (msr_val >> 4) & 0x1 ))
        local thermal_threshold1=$(( (msr_val >> 6) & 0x1 ))
        local thermal_threshold2=$(( (msr_val >> 7) & 0x1 ))
        local power_limit=$(( (msr_val >> 10) & 0x1 ))
        local current_limit=$(( (msr_val >> 11) & 0x1 ))
        
        echo "  Thermal status MSR: 0x${msr_val}"
        [[ $thermal_status -eq 1 ]] && warn "  Thermal status: ACTIVE" || ok "  Thermal status: OK"
        [[ $prochot -eq 1 ]] && warn "  PROCHOT: ASSERTED" || ok "  PROCHOT: Clear"
        [[ $crit_temp -eq 1 ]] && err "  CRITICAL TEMP: TRIGGERED" || ok "  Critical temp: OK"
        [[ $thermal_threshold1 -eq 1 ]] && warn "  Thermal threshold 1: HIT"
        [[ $thermal_threshold2 -eq 1 ]] && warn "  Thermal threshold 2: HIT"
        [[ $power_limit -eq 1 ]] && warn "  Power limit: REACHED"
        [[ $current_limit -eq 1 ]] && warn "  Current limit: REACHED"
    else
        warn "  MSR access not available (try: sudo modprobe msr)"
    fi
    
    # Check cpufreq scaling
    if [[ -d /sys/devices/system/cpu/cpufreq ]]; then
        hdr "CPU Frequency Scaling"
        local cpus
        cpus=$(ls /sys/devices/system/cpu/cpufreq 2>/dev/null || true)
        for cpu in $cpus; do
            if [[ -f "/sys/devices/system/cpu/cpufreq/$cpu/scaling_cur_freq" ]]; then
                local freq min max
                freq=$(cat "/sys/devices/system/cpu/cpufreq/$cpu/scaling_cur_freq")
                min=$(cat "/sys/devices/system/cpu/cpufreq/$cpu/scaling_min_freq")
                max=$(cat "/sys/devices/system/cpu/cpufreq/$cpu/scaling_max_freq")
                freq=$((freq / 1000))
                min=$((min / 1000))
                max=$((max / 1000))
                printf "  %-10s %4d MHz (min: %4d, max: %4d)\n" "$cpu" "$freq" "$min" "$max"
            fi
        done
    fi
}

# =============================================================================
# HELP
# =============================================================================
cmd_help() {
    cat << 'EOF'

huawei-thermal — Thermal management for Huawei MateBook

Usage: huawei-thermal <command> [subcommand] [args]

Commands:
  status              Show current thermal status (temperatures, fans, power)
  fan status          Check fan control availability
  fan set <level>     Manually set fan speed level (if supported)
  fan auto            Enable automatic fan control
  profile status      Show current thermal/power profile
  profile quiet       Set low-power/quiet profile
  profile balanced    Set balanced profile  
  profile performance Set high-performance profile
  monitor [seconds]   Continuous temperature monitoring (default: 2s)
  throttle            Check thermal throttling status
  undervolt status    Show CPU undervolt status (requires intel-undervolt)
  undervolt apply [mV] Apply CPU undervolt (e.g., -50 for 50mV)
  undervolt reset     Reset undervolt to 0mV
  help                Show this help message

Examples:
  huawei-thermal status
  sudo huawei-thermal fan set 128
  sudo huawei-thermal profile performance
  huawei-thermal monitor 5
  sudo huawei-thermal undervolt apply -50

EOF
}

# =============================================================================
# Main dispatcher
# =============================================================================
main() {
    local cmd="${1:-status}"
    shift 2>/dev/null || true
    
    case "$cmd" in
        status|s)           cmd_status "$@" ;;
        fan|f)              cmd_fan "$@" ;;
        profile|prof|p)     cmd_profile "$@" ;;
        monitor|mon|m)      cmd_monitor "$@" ;;
        throttle|throt|t)   cmd_throttle "$@" ;;
        undervolt|uv|u)     cmd_undervolt "$@" ;;
        help|-h|--help)     cmd_help ;;
        *)
            err "Unknown command: $cmd"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
