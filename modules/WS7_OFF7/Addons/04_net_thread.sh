#!/system/bin/sh
apply() {
    setprop net.tcp.buffersize.wifi 524288,1048576,2097152,262144,524288,1048576
    setprop net.tcp.low_latency 1
    settings put global private_dns_mode hostname
    settings put global private_dns_specifier one.one.one.one
    settings put global wifi_suspend_optimizations_enabled 0
    settings put global wifi_watchdog_on 0
}
reset() {
    setprop net.tcp.buffersize.wifi ""
    setprop net.tcp.low_latency ""
    settings put global private_dns_mode off
    settings delete global private_dns_specifier
    settings delete global wifi_suspend_optimizations_enabled
    settings delete global wifi_watchdog_on
}
[ "$1" = "apply" ] || [ "$1" = "on" ] && apply || reset
