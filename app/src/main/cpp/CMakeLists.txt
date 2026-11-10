# =============================================================================
#  Núcleo nativo do pack (C via NDK).
#
#  Por que C aqui: a telemetria do monitor (RAM, CPU, temperatura, frequência) é
#  feita hoje por shell (abre um `sh` a cada 4s). Em C a mesma leitura é uma
#  leitura de arquivo — sem fork, sem binder, sem custo de shell. É o que permite
#  medir MAIS e com menos gasto, que era o objetivo de encaixar uma linguagem
#  nova sem mexer no que já funcionava.
#
#  O código é defensivo: qualquer arquivo ausente devolve -1 em vez de quebrar
#  (o mesmo contrato dos scripts, que nunca inventam número).
# =============================================================================
cmake_minimum_required(VERSION 3.22.1)
project(otmcore C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_library(otmcore SHARED otm_native.c)

target_compile_options(otmcore PRIVATE
    -Wall -Wextra -O2 -fvisibility=hidden -ffunction-sections -fdata-sections)

target_link_options(otmcore PRIVATE -Wl,--gc-sections)

# 16 KB page size (Android 15+): sem isto o linker deixa o segmento em 4 KB e o
# app pode ser recusado em aparelho novo. Vale para NDK r27+.
target_link_options(otmcore PRIVATE "-Wl,-z,max-page-size=16384")
