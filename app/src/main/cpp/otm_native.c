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
