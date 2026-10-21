// SPDX-License-Identifier: Apache-2.0
// Extraído de RikkaApps/Shizuku-API (aidl/src/main/aidl/moe/shizuku/server/IShizukuService.aidl).
// Mantido apenas o método usado pelo app: newProcess (transação 7).
package moe.shizuku.server;

import moe.shizuku.server.IRemoteProcess;

interface IShizukuService {
    IRemoteProcess newProcess(in String[] cmd, in String[] env, in String dir) = 7;
}
