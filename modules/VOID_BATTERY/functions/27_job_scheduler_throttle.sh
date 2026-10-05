#!/system/bin/sh
# VOID BATTERY v9.1 — Job Scheduler Throttle
# IMPROVED: Better throttling for BALANCED — limits background work without
# affecting foreground apps

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL)
        vb_devconfig jobscheduler qc_max_job_count_per_allowed_time 2
        vb_devconfig jobscheduler enable_api_quotas true
        vb_devconfig jobscheduler min_ready_non_active_jobs_count 1
        vb_devconfig jobscheduler bg_critical_job_count 1
        vb_devconfig jobscheduler max_num_active_jobs 3
        ;;
    POWERSAVE)
        vb_devconfig jobscheduler qc_max_job_count_per_allowed_time 4
        vb_devconfig jobscheduler enable_api_quotas true
        vb_devconfig jobscheduler bg_critical_job_count 2
        vb_devconfig jobscheduler max_num_active_jobs 4
        ;;
    ECO)
        vb_devconfig jobscheduler qc_max_job_count_per_allowed_time 6
        vb_devconfig jobscheduler enable_api_quotas true
        vb_devconfig jobscheduler bg_critical_job_count 3
        ;;
    IDLE|BALANCED)
        # IMPROVED: Moderate throttle even for BALANCED
        vb_devconfig jobscheduler qc_max_job_count_per_allowed_time 8
        vb_devconfig jobscheduler enable_api_quotas true
        vb_devconfig jobscheduler bg_critical_job_count 4
        ;;
esac
vb_log "JOBS" "Job scheduler throttled"
