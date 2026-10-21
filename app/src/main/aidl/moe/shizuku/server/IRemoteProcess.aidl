// SPDX-License-Identifier: Apache-2.0
// Extraído de RikkaApps/Shizuku-API (aidl/src/main/aidl/moe/shizuku/server/IRemoteProcess.aidl).
package moe.shizuku.server;

interface IRemoteProcess {
    ParcelFileDescriptor getOutputStream();
    ParcelFileDescriptor getInputStream();
    ParcelFileDescriptor getErrorStream();
    int waitFor();
    int exitValue();
    void destroy();
    boolean alive();
    boolean waitForTimeout(long timeout, String unit);
}
