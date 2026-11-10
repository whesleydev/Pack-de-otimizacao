// =============================================================================
//  otm_native.c - núcleo nativo (C) do pack.
//
//  O que ele faz que o shell faz mal: LER o aparelho sem abrir um processo. Cada
//  função aqui é uma leitura de /proc ou /sys — o mesmo dado que os scripts
//  pegam, mas sem o custo de fork+binder de um `sh` novo. O monitor do flutuante
//  chama isto a cada ciclo em vez de rodar `panel-stats.sh`.
//
//  Regra (a mesma dos scripts): NUNCA inventar. Arquivo ausente ou valor fora de
//  faixa devolve -1 e quem chamou mostra "—".
//
//  Exposto ao Kotlin por JNI (OtmNative.kt). O JNI é a ponte oficial do Android
//  para código nativo; nada de FFI exótico.
// =============================================================================
#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <time.h>

#define JNI_EXPORT __attribute__((visibility("default")))

// --- utilidades --------------------------------------------------------------

// lê o primeiro inteiro de um arquivo; -1 se não existir/não for número
static long read_long_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    long v = -1;
    if (fscanf(f, "%ld", &v) != 1) v = -1;
    fclose(f);
    return v;
}

// lê o primeiro número (com casa decimal) de um arquivo; -1 se não existir
static double read_double_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    double v = -1;
    if (fscanf(f, "%lf", &v) != 1) v = -1;
    fclose(f);
    return v;
}

// --- RAM (igual ao MemAvailable dos scripts) ---------------------------------
// Devolve kB de RAM disponível, ou -1. MemAvailable é o número certo (já conta
// cache reclamável); MemFree engana em aparelho com cache cheio.
JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_ramAvailableKb(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f) return -1;
    char line[256];
    long v = -1;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "MemAvailable:", 13) == 0) {
            if (sscanf(line + 13, "%ld", &v) != 1) v = -1;
            break;
        }
    }
    fclose(f);
    return v;
}

JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_ramTotalKb(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f) return -1;
    char line[256];
    long v = -1;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "MemTotal:", 9) == 0) {
            if (sscanf(line + 9, "%ld", &v) != 1) v = -1;
            break;
        }
    }
    fclose(f);
    return v;
}

// --- temperatura máxima (mC) -------------------------------------------------
// Percorre as zonas térmicas e devolve a MAIOR em mili-graus, ou -1. Algumas
// zonas reportam décimos de grau (< 1000) — normaliza para mC.
JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_maxThermalMilliC(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    DIR *d = opendir("/sys/class/thermal");
    if (!d) return -1;
    struct dirent *e;
    long best = -1;
    char path[512];
    while ((e = readdir(d))) {
        if (strncmp(e->d_name, "thermal_zone", 12) != 0) continue;
        snprintf(path, sizeof(path), "/sys/class/thermal/%s/temp", e->d_name);
        long t = read_long_file(path);
        if (t <= 0) continue;
        // zonas reportam em mC (45000) ou em décimos de grau (450) — normaliza
        if (t < 1000) t *= 100;
        if (t > best) best = t;
    }
    closedir(d);
    return best;
}

// --- frequência atual do núcleo mais rápido ---------------------------------
// Em kHz, ou -1. Lê scaling_cur_freq de cada cpu e devolve a maior — é o número
// que o usuário reconhece como "a CPU está a X GHz".
JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_currentCpuFreqKhz(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    DIR *d = opendir("/sys/devices/system/cpu");
    if (!d) return -1;
    struct dirent *e;
    long best = -1;
    char path[512];
    while ((e = readdir(d))) {
        if (strncmp(e->d_name, "cpu", 3) != 0) continue;
        if (e->d_name[3] < '0' || e->d_name[3] > '9') continue;
        snprintf(path, sizeof(path),
                 "/sys/devices/system/cpu/%s/cpufreq/scaling_cur_freq", e->d_name);
        long f = read_long_file(path);
        if (f > best) best = f;
    }
    closedir(d);
    return best;
}

// --- carga da CPU em % (0..100) ----------------------------------------------
// Diferença de jiffies desde a última chamada do MESMO processo. A primeira
// chamada devolve -1 (não há base de comparação) — nunca chuta.
JNI_EXPORT jint JNICALL
Java_com_otm_pack_OtmNative_cpuUsagePercent(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    static unsigned long long prev_total = 0, prev_idle = 0;
    FILE *f = fopen("/proc/stat", "r");
    if (!f) return -1;
    char line[512];
    if (!fgets(line, sizeof(line), f)) { fclose(f); return -1; }
    fclose(f);
    unsigned long long u=0,n=0,s=0,i=0,w=0,irq=0,sirq=0,steal=0;
    if (sscanf(line, "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
               &u,&n,&s,&i,&w,&irq,&sirq,&steal) < 4) return -1;
    unsigned long long idle = i + w;
    unsigned long long total = u+n+s+i+w+irq+sirq+steal;
    if (prev_total == 0) { prev_total = total; prev_idle = idle; return -1; }
    unsigned long long dt = total - prev_total, di = idle - prev_idle;
    prev_total = total; prev_idle = idle;
    if (dt == 0) return -1;
    int pct = (int)((dt - di) * 100ULL / dt);
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    return pct;
}

// --- uptime em segundos ------------------------------------------------------
JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_uptimeSeconds(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    double up = read_double_file("/proc/uptime");
    if (up < 0) return -1;
    return (jlong)up;
}

// --- número de núcleos -------------------------------------------------------
JNI_EXPORT jint JNICALL
Java_com_otm_pack_OtmNative_cpuCores(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    long n = sysconf(_SC_NPROCESSORS_CONF);
    return (n > 0) ? (jint)n : -1;
}

// =============================================================================
//  Telemetria estendida (painel flutuante)
//  Tudo aqui segue a mesma regra: leitura direta de /proc e /sys, -1 quando o
//  aparelho não expõe o dado. Nada de estimativa, nada de valor "plausível".
// =============================================================================

// --- temperatura de UMA zona pelo TIPO ---------------------------------------
// Recebe o nome do tipo (ex.: "battery", "cpu", "gpu", "skin") e devolve a maior
// temperatura entre as zonas cujo `type` contém esse texto, em mili-graus. É o
// que permite separar "bateria quente" de "SoC quente" — coisas diferentes.
JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_thermalZoneMilliC(JNIEnv *env, jclass clazz, jstring jtype) {
    (void)clazz;
    if (!jtype) return -1;
    const char *want = (*env)->GetStringUTFChars(env, jtype, NULL);
    if (!want) return -1;
    DIR *d = opendir("/sys/class/thermal");
    long best = -1;
    if (d) {
        struct dirent *e;
        char tpath[512], zpath[512], type[128];
        while ((e = readdir(d))) {
            if (strncmp(e->d_name, "thermal_zone", 12) != 0) continue;
            snprintf(tpath, sizeof(tpath), "/sys/class/thermal/%s/type", e->d_name);
            FILE *tf = fopen(tpath, "r");
            if (!tf) continue;
            if (!fgets(type, sizeof(type), tf)) { fclose(tf); continue; }
            fclose(tf);
            if (!strstr(type, want)) continue;   // casa pelo tipo, não pelo índice
            snprintf(zpath, sizeof(zpath), "/sys/class/thermal/%s/temp", e->d_name);
            long t = read_long_file(zpath);
            if (t <= 0) continue;
            if (t < 1000) t *= 100;              // décimos de grau -> mC
            if (t > best) best = t;
        }
        closedir(d);
    }
    (*env)->ReleaseStringUTFChars(env, jtype, want);
    return best;
}

// --- bateria -----------------------------------------------------------------
// Lê um valor do nó de energia. Prefere o nó do `battery` (não do `usb`/`ac`).
static long read_power_supply(const char *node) {
    DIR *d = opendir("/sys/class/power_supply");
    if (!d) return -1;
    struct dirent *e;
    long v = -1;
    char path[512];
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        snprintf(path, sizeof(path), "/sys/class/power_supply/%s/%s", e->d_name, node);
        long r = read_long_file(path);
        if (r != -1) { v = r; break; }
    }
    closedir(d);
    return v;
}

// Corrente instantânea em micro-ampères (sinal preservado: negativo = descarga).
JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_batteryCurrentUa(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    return read_power_supply("current_now");
}

// Tensão da bateria em micro-volts.
JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_batteryVoltageUv(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    return read_power_supply("voltage_now");
}

// Carga em % (0..100).
JNI_EXPORT jint JNICALL
Java_com_otm_pack_OtmNative_batteryCapacityPct(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    long c = read_power_supply("capacity");
    if (c < 0 || c > 100) return -1;
    return (jint)c;
}

// --- pressão de memória (PSI) ------------------------------------------------
// `some avg10` = % do tempo em que ALGUMA tarefa ficou parada por falta de
// memória, na média dos últimos 10 s. É o melhor sinal de "a RAM está apertando"
// — melhor que "RAM livre", que engana com cache cheio. Devolve % * 100 (centésimos).
JNI_EXPORT jint JNICALL
Java_com_otm_pack_OtmNative_memPressureSome(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    FILE *f = fopen("/proc/pressure/memory", "r");
    if (!f) return -1;
    char line[256];
    int v = -1;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "some", 4) != 0) continue;
        double avg10 = 0;
        if (sscanf(line, "some avg10=%lf", &avg10) == 1) v = (int)(avg10 * 100.0);
        break;
    }
    fclose(f);
    return v;
}

// --- swap/zram em uso (kB) ---------------------------------------------------
JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_swapUsedKb(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f) return -1;
    char line[256];
    long used = -1;
    while (fgets(line, sizeof(line), f)) {
        long v = -1;
        if (strncmp(line, "SwapTotal:", 10) == 0) {
            if (sscanf(line + 10, "%ld", &v) == 1 && used < 0) used = v;
        } else if (strncmp(line, "SwapFree:", 9) == 0) {
            long freev = -1;
            if (sscanf(line + 9, "%ld", &freev) == 1 && used >= 0) {
                used -= freev;
                if (used < 0) used = 0;
                break;
            }
        }
    }
    fclose(f);
    return used;
}

// --- rede: bytes recebidos/enviados desde o boot -----------------------------
// Soma todas as interfaces exceto o loopback. Serve para o painel mostrar o
// tráfego real e a taxa (a diferença entre duas leituras).
static long read_net_bytes(const char *want_rx) {
    FILE *f = fopen("/proc/net/dev", "r");
    if (!f) return -1;
    char line[512];
    long total = 0;
    int found = 0;
    while (fgets(line, sizeof(line), f)) {
        char *colon = strchr(line, ':');
        if (!colon) continue;               // cabeçalho
        char ifname[64];
        size_t n = (size_t)(colon - line);
        if (n >= sizeof(ifname)) continue;
        memcpy(ifname, line, n);
        ifname[n] = '\0';
        char *p = ifname;
        while (*p == ' ') p++;
        if (strcmp(p, "lo") == 0) continue; // loopback não conta
        unsigned long long rx = 0, tx = 0;
        if (sscanf(colon + 1, "%llu %*u %*u %*u %*u %*u %*u %*u %llu", &rx, &tx) < 1) continue;
        total += (long)(want_rx ? rx : tx);
        found = 1;
    }
    fclose(f);
    return found ? total : -1;
}

JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_netRxBytes(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    return read_net_bytes("rx");
}

JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_netTxBytes(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    return read_net_bytes(NULL);
}

// --- GPU: carga (%) ----------------------------------------------------------
// Adreno (kgsl) expõe `gpu_busy_percentage`; Mali expõe `utilization`. Se nenhum
// existir, devolve -1 (nada de estimar pela CPU).
JNI_EXPORT jint JNICALL
Java_com_otm_pack_OtmNative_gpuLoadPct(JNIEnv *env, jclass clazz) {
    (void)env; (void)clazz;
    static const char *paths[] = {
        "/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage",
        "/sys/class/kgsl/kgsl-3d0/gpubusy",
        "/sys/class/devfreq/gpufreq/gpu_load",
        "/sys/kernel/gpu/gpu_busy",
        "/sys/class/misc/mali0/device/utilization",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        long v = read_long_file(paths[i]);
        if (v >= 0 && v <= 100) return (jint)v;
    }
    return -1;
}

// --- frequência máxima de um núcleo (kHz) ------------------------------------
// `cpuinfo_max_freq` é o teto do cluster daquele núcleo. É o que o painel mostra
// como "clock máximo" sem abrir processo nenhum.
JNI_EXPORT jlong JNICALL
Java_com_otm_pack_OtmNative_cpuMaxFreqKhz(JNIEnv *env, jclass clazz, jint core) {
    (void)env; (void)clazz;
    if (core < 0) return -1;
    char path[512];
    snprintf(path, sizeof(path),
             "/sys/devices/system/cpu/cpu%d/cpufreq/cpuinfo_max_freq", (int)core);
    return read_long_file(path);
}

// --- governador atual da CPU (string) ----------------------------------------
JNI_EXPORT jstring JNICALL
Java_com_otm_pack_OtmNative_cpuGovernor(JNIEnv *env, jclass clazz) {
    (void)clazz;
    FILE *f = fopen("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor", "r");
    if (!f) return NULL;
    char buf[64];
    jstring out = NULL;
    if (fgets(buf, sizeof(buf), f)) {
        size_t n = strlen(buf);
        while (n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r')) buf[--n] = '\0';
        if (n > 0) out = (*env)->NewStringUTF(env, buf);
    }
    fclose(f);
    return out;
}
