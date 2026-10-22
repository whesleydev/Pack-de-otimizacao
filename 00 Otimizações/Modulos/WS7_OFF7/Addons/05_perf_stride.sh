#!/system/bin/sh
apply() {
    cmd power set-fixed-performance-mode-enabled true >/dev/null 2>&1
    setprop debug.performance.tuning 1
    setprop debug.hwui.renderer opengl
    setprop debug.sf.disable_backpressure 1
    setprop debug.sf.latch_unsignaled 1
}
reset() {
    cmd power set-fixed-performance-mode-enabled false >/dev/null 2>&1
    setprop debug.performance.tuning ""
    setprop debug.hwui.renderer ""
    setprop debug.sf.disable_backpressure ""
    setprop debug.sf.latch_unsignaled ""
}
[ "$1" = "apply" ] || [ "$1" = "on" ] && apply || reset
