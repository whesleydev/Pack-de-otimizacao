#!/system/bin/sh
# VOID BATTERY v9.1 — Light Doze Fine-Tuning
# IMPROVED: Added BALANCED profile for gentle light doze tuning

vb_log "LDOZE" "Light doze tuning — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL)
        vb_devconfig deviceidle light_after_inactive_to 30000
        vb_devconfig deviceidle light_pre_idle_to 60000
        vb_devconfig deviceidle light_idle_to 180000
        vb_devconfig deviceidle light_idle_factor 1.5
        vb_devconfig deviceidle light_max_idle_to 600000
        vb_devconfig deviceidle light_idle_maintenance_min_budget 15000
        vb_devconfig deviceidle light_idle_maintenance_max_budget 30000
        vb_log "LDOZE" "Ultra-aggressive light doze"
        ;;
    POWERSAVE)
        vb_devconfig deviceidle light_after_inactive_to 60000
        vb_devconfig deviceidle light_pre_idle_to 120000
        vb_devconfig deviceidle light_idle_to 300000
        vb_devconfig deviceidle light_idle_factor 2.0
        vb_devconfig deviceidle light_max_idle_to 900000
        vb_log "LDOZE" "Aggressive light doze"
        ;;
    ECO|IDLE)
        vb_devconfig deviceidle light_after_inactive_to 120000
        vb_devconfig deviceidle light_pre_idle_to 180000
        vb_devconfig deviceidle light_idle_to 600000
        vb_devconfig deviceidle light_max_idle_to 1800000
        vb_log "LDOZE" "Moderate light doze"
        ;;
    BALANCED)
        # IMPROVED: Gentle light doze — faster idle entry when screen off
        # Does NOT affect active use at all
        vb_devconfig deviceidle light_after_inactive_to 180000
        vb_devconfig deviceidle light_pre_idle_to 300000
        vb_devconfig deviceidle light_idle_to 900000
        vb_devconfig deviceidle light_max_idle_to 3600000
        vb_log "LDOZE" "Gentle light doze (balanced)"
        ;;
esac
