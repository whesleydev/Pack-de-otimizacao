### Stellar v22.0 (Voyaging-Astralist) ###
Banner URL: ./assets/Stellar-V22.png
- Modularized technical daemon architecture and decoupled the Web User Interface
- Implemented native Fast Energy Aware Scheduling (FEAS) engine
- Replaced shell commands with direct libc system calls and procfs scanning
- Consolidated and integrated Trinity CPU scheduler algorithms
- Added Custom GPU Governor configuration per profile in daemon and WebUI
- Added system-level device spoofing to unlock high refresh rate and FPS in games
- Added native system toast notification pipeline via Android Binder IPC
- Added force refresh rate injection and automatic 60Hz power-saving switching
- Redesigned uninstaller dialog with granular component removal and tweak rollback
- Replaced shell polling with event-driven TaskStackListener and PackageManager game detection
- Integrated universal Android AccountManager Binder query (2ms) for license verification
- Optimized thread priority injection, cluster-based core pinning, and dynamic I/O schedulers
- Implemented state cache structure to eliminate redundant sysfs hardware writes
- Added automated first-boot configuration matched to hardware display capabilities

**AfterRelease2:**
- Fix license registry unknown at nonroot environment
- Adding ADPF android property at nonroot devices

**AfterRelease3:**
- Fix undetected foreground on various pure AOSP such like lineage
- Rework foreground logic is only reset profile when process is end at recent launcher 
- Change method system settings & system property application to native call
- Rework logic HW_MAP only trigger for root environment 
- Fix license registry dump binder deadlock pipeline

**AfterRelease4:**
- Adding support binary 32bit (arm) architecture device 
- Fixed issue foreground detection by using multiple fallback method
- Update spoofing device range to game inference & update database spoofing list

**AfterRelease5:**
- Fix Android 10-11 foreground detection cold start issue
- Handle WebUI app list querying natively via daemon IPC
- Improve WebUI performance by replacing shell commands with native Rust calls
- Restore Heuristic Mode with refined dynamic variance logic
- Fix device audio loss issue caused by device spoofing
- Add framework overlay state caching and automatic profile reset
- Replace external binary calls with direct native system calls


### Stellar V21.0 (Orbitals-Desk) ###
Banner URL: ./assets/Stellar-V21.png
- Update Logic Normal Mode: Revert behavior to default Android values
- Fix Slow Charging Issue on some devices
- Add Backup & Restore, encode raw data to Base64
- Implement Stellar AI Memory Pleasure
- Add Stellar AI Learning Caches: reduce calculation on startup
- Remove Networking Tweak, remove SurfaceFlinger prop
- Remove device_config constant junk to fix bootloop issue
- Enhance Stellar AI Profile Case
- Remove separate GMS Doze, Battery Saving; merged into Utility Tool
- Improve Logic Backup Renderer & Switch Renderer 
- Improve Storage Lifespan identification
- Improve Visual UI and fix visual bugs
- Minor improvements and optimizations

**Hotfix & Optimization:**
- Remove SurfaceFlinger optimizations 
- Fix Activation Stellar logic 
- Fix undetected apps new process generate
- Add some gamelist package

### Stellar V20.2 (Bon-Voyage) ###
Banner URL: ./assets/Stellar-V17-V20.2.jpg
- Hotfix and refined from 20.x

### Stellar V20.1 (Bon-Voyage) ###
Banner URL: ./assets/Stellar-V17-V20.2.jpg
- Refactored logic for Stellar AI personalization profile
- Removed network disable during deep sleep state
- Eliminated dumpsys usage within daemon processes
- Added networking options for licensed users
- Fixed issue where licensed status was undetectable
- Enhanced and aligned translation strings
- Introduced debugging options
- Improved Game API verification logic
- Fixed storage lifespan detection mechanism
- Redesigned several UI components
- Miscellaneous improvements and optimizations

### Stellar V20.0 (Bon-Voyage) ###
Banner URL: ./assets/Stellar-V17-V20.2.jpg
- App Profile system fully rewritten with new logic pipeline
- Per-app Renderer config: HWUI mode & graphics backend
- Per-app Refresh Rate Control via Game API (A13+)
- Per-app Render Downscaling via Game API (A13+)
- Per-app Thermal modification variative method
- Full WebUI redesign and interaction logic overhaul
- Global Hwui & backend Renderer configuration 
- Added New languages ar, hi, fr, de, it, ko, pl, vi, tr 
- Per-app DVFS policy configuration (variates GPU/CPU) 
- Scheduler Priority: granular thread/process priority targeting
- Asset Preloader with 2 intensity levels (Standard / Maximum)
- App Monkey Runner shortcut from profile view
- Direct App Info Android Settings shortcut
- Hot Reload for App List content without full restart
- Refined Rust structure daemon to native parsing pipeline
- Removed activity_manager entries from device_config
- Added targeted device_config keys for Job Scheduler 

### Stellar V19.0 (Reversing) ###
Banner URL: ./assets/Stellar-V17-V20.2.jpg
- Performed core daemon code refactoring for optimization
- Implemented complete Web UI redesign
- Updated Stellar AI profiler with adaptive rule adjustments
- Enhanced monitoring for context frame awareness
- Improved scaling adjustment queue logic for predictions
- Deprecated and removed GMS Doze and Clear RAM options
- Refined new optimization nonroot tids
- Removed VM-based kernel tweaking module
- Integrated additional kernel scheduler support
- Resolved monitoring loop hang/stuck condition
- Patched battery drain issue in rooted environment
- Streamlined device_config structure and reduced bloat
- Introduced Auto Lock Frequencies configuration option
- Fixed hardcoded path in AxManager latest release check
- Removed legacy Backup & Restore module
- Conducted code cleanup across Web UI and binary
- Finalized full Web UI translation updates
- Removed outdated test device_config entries
- Added SurfaceFlinger latency optimization parameters

### Stellar V18.5 (Un-revealing) ###
Banner URL: ./assets/Stellar-V17-V20.2.jpg
- Fixed the Hardware Visibility option.
- Enhanced error logging for better debugging.
- Optimized and minimized the logging daemon's resource use.
- Added new device-specific optimizations in device_config.
- Updated kernel parameters per performance profile.
- Improved overall environment stability for Root & Non-Root.
- Fixed an issue with the Flow state license.
- Removed the deprecated Backup & Restore feature.
- Added Markdown formatting support to this changelog.
- Various other minor optimizations and fixes.

### Stellar V18.0 (Un-revealing) ###
Banner URL: ./assets/Stellar-V17-V20.2.jpg
- First impact release for hybrid Unrooted & Rooted environment
- Just a bit Redesign to webui with supported multi color basic and support adapt environment to feature
- Added Game Boost Priority Frame Aware Scheduled
- Introduce V18 Per-app profile focussed
- Restructured daemon to adapt 2 environment
- Refactor Game Optimization Root/NonRoot
- New: Minimize kernel scheduled per-profile (default)
- New Scaling Support: Advanced DVFS (calc closest range freq as available automated)
- Update GPU source mediatek paths
- Support efficient by add stellar_helper workaround replaced for profile.
- Pro feature removed & Refined: Battery saver category, Stellar Engineer
- Removed & Refined: Hibernate, Limit GPU DVFS, Set CPU max freq, Lite mode, kernel scheduler
- Totally remove: Surfaceflinger, Remove traces, Mitsu/Zeta. Preference cat
- Add New GMS Doze automated
- Add New Clear Ram Background
- Many more

### Stellar V17.0 (Un-existence) ###
Banner URL: ./assets/Stellar-V17-V20.2.jpg
- First Impact hybrid update choose usage pro-reguler
- Stellar AI: Revamp 2 profiles value by scaling loads
- Redesign whole User Interface
- Add New: Guide Mark information option
- Add New: Banner custom image
- Fixed: Reapply game session while playing
- Replace: Collab script Zeta -> Mitsu tweak
- Add New: AMOLED theme
- Add new information for tuning cpu & io
- Update: Surfaceflinger source
- Refine start code preloading at boots up
- Set CPU max freq for default while game
- Fixed game race (again), game undetected
- Logic: Use Sub-Interval to loop threads
- Many more

### Stellar V16.0 (Midnight-Terror) ###
Banner URL: ./assets/Stellar-V16.jpg
- Added: New device for NVIDIA Tegra,Kirin,Intel,Google Tensor SoCs
- Fixed: reduce heat effect limit backround
- Fixed: Race condition causing an incorrect activity lock state during game
- Fixed: failure in customize execution toast installing
- Re-Implent: kernel I/O scheduler section interface
- Updated: Language context and string resources
- Updated: Game data list package to build 25/09/20
- Adjusted: Preload default algorithm and sufficiency budget parameters
- Refactor: Detection list foreground, background more intrutive
- Added: Restored DDR bus support for Snapdragon platforms
- Refactor: Cleaning code remove all harmful sloppy
- Redesign: Change Ui look 5%, 10% optimization webui light
- Added: In main installer add 'Pro Tips' helping user reach
- Added: Add checking SU compatibility in customize.sh
- Fixed: Fix permission installer stellar issue, rare case issue not permitted
- Changed: Default powersave policy now 20% DVFS limit
- Many more

### Stellar V15 (Kizuna-Divines) ###
Banner URL: ./assets/Stellar-V15.jpg
- Set Background Paused Generous Idle State for better CPU usage.
- Preload Default logic updated with 4 action changes.
- Preload section is now determined by checking the current free memory.
- Added new languages for WebUI: Indonesian, Chinese, English, Brazilian, Spanyol, Russian.
- Changed the appearance of the logging template.
- Removed the 'Start Daemon' button from the WebUI.
- Added a 'See Logs' button for easy access to logging interface.
- Re-added Toast Info for when a game is applied or closed.
- Refactored the daemon state/polling loop progress.
- Changed config/flag files to be readable with config.json formatting.
- Added a Jumpscare Popup easter egg when the WebUI is opened.
- Factored Profiles Executes Files to read the new config and tidy up syntax.
- Added a transparent Changelog Build section.
- Removed Blur Effect from WebUI surface and minimized shadows for a lighter feel.
- General improvements in Daemon Optimization and bug fixing.
- Many more.

### Stellar V14 (The-Egoist) ###
Banner URL: ./assets/Stellar-V14.jpg
- Removed Surfaceflinger optimized strings due to negative effects.
- Removed IRQ Affinity as it had no effect.
- Removed Prioritize GPU focus due to negative side effects.
- Introduced smart prioritize threads to scale which threads need to execute first.
- Added a Default Theme Accent Color to the WebUI.
- Added Dumpsys Stress Checking.
- Improved various thread optimizations from the previous version.
- Removed HMP tweaking.
- Re-added CPU max frequency as an option.
- Remade the logic for how Zeta Tweak is applied.
- General improvements in daemon optimization and bug fixing.

### Stellar V13 (Hiroroki) ###
Banner URL: ./assets/Stellar-V13.jpg
- Fixed a 'Race condition' that occurred when switching control profiles.
- Removed CPU max frequency value due to issues with governors.
- Added Prioritize GPU focus with a balanced approach.
- Added IRQ Affinity for Low-Resolution touch input.
- Attempted to optimize Surfaceflinger for potential FPS gains.
- General improvements in daemon optimization and bug fixing.

### Stellar V12 (Bahamut) ###
Banner URL: ./assets/Stellar-V12.jpg
- Redesigned the User Interface Info and improved the Light UI theme.
- Brought back the Preference Setting menu.
- Introduced Hibernate mode.
- Added a Reduce Heat option.
- Added a Kernel Tweak Scheduler.
- Improved execution of Zeta Tweak to ensure it works correctly.
- Added Adaptive Surfaceflinger.
- Changed Preload to be an optional setting.
- Improved Skip Performance to skip overall tweaks.
- Introduced a Backup & Restore code feature.
- Changed logic for how special packages are prioritized.
- General improvements in daemon optimization and bug fixing.

### Stellar V11 (Chronicles) ###
Banner URL: ./assets/Stellar-V11.jpg
- UI redesign with Material You (Monet) theme.
- Module size reduced to under 400KB.
- Improved installer SoC detection.
- Set Preload for games as a default option.
- Lite mode now reduces CPU/GPU usage by 50%.
- Improved prioritization on game process IDs (PID).
- Fixed foreground detection lock core system optimizations.
- Fixed WebUI save package search bar bug.
- Fixed prop compatibility issues on various devices.
- Integrated collaboration scripts for Zeta Tweak (Beta).
- General improvements in daemon optimization and bug fixing.

### Stellar V10 (Chrochy) ###
Banner URL: ./assets/Stellar-V10.jpg
- Fully refactored code with simpler methods.
- Installer now includes subjective SoC detection.
- Removed the logic for boosting frequency based on load due to instability and heat.
- Added a Search bar to the gamelist to check if a package already exists.
- Shipped a new Material design for the UI.
- Removed the save log button from the UI; logs are now used only when needed.
- General improvements in daemon optimization and bug fixing.

### Stellar V9 (Hitori-Bocchi) ###
Banner URL: ./assets/Stellar-V9.0.jpg
- Refactored game list array passing to a simple 1-line implementation.
- Used symlinks for custom binaries for KSU/APatch compatibility.
- Refactored filtering logic for easier array filtering.
- New logic for adaptive boost frequency based on usage.
- Added a new item for filtering I/O scheduler.
- Removed SHA256 verification.
- Improved Lite mode by limiting DVFS to 50%.
- Improved Niceness Conjuring to be more predictable, leaving child processes alone.
- Improved logging method to be more direct and proper.
- Numerous improvements in daemon flow and bug fixing.

### Stellar V8.5 (Ex-エコー) ###
Banner URL: ./assets/Stellar-V7.5-8.5.jpg
- Update: Enhanced preload libraries with improved app selection and logic.
- Fix: Resolved an undetected dumpsys issue.
- Feature: Added a WebUI option to disable Google Analytics & Ads.
- Optimization: Reduced string & prop operations to prevent bottlenecks on Xiaomi devices.
- Feature: Implemented FpsGo support for MediaTek devices with optimized parameters.
- Improvement: System Logging is now accessible via a button with API interaction.
- Fix: Corrected unmatched CPU governor assignments.
- Improvement: Enhanced logging methodology with API integration.
- Fix: Resolved daemon termination issues on certain devices.
- Various bug fixes from the previous version.

### Stellar V8 (Serenity) ###
Banner URL: ./assets/Stellar-V7.5-8.5.jpg
- Added Preload Library (Beta) to the WebUI section.
- Implemented Lite Mode (Beta) inspired by Encore.
- Minimized MTK profiles by cleaning up DVFS parameters.
- Removed spoofing functionality due to implementation issues.
- Improved GED parameter values for MTK devices.
- Fixed SPM & PPM configuration mismatches.
- Corrected unmatched CPU governor settings in MTK profiles.
- Reduced real-time priority overhead by 20%.
- Decreased daemon CPU usage by 30% through optimized app detection.
- Removed CPU affinity settings that caused unstable CPU utilization.
- Added Schedtune support for devices with /dev/stune.
- Various miscellaneous improvements.

### Stellar V7.8 (Twilight) ###
Banner URL: ./assets/Stellar-V7.5-8.5.jpg
- Removed Niceness high level due to battery drain.
- Implemented CPU affinity to optimize CPU.
- Added profiles for Snapdragon, Mediatek, Exynos, and Unisoc.
- Disabled TMU thermal for Mali GPUs.
- Set Snapdragon component 'bus_dcvs' to max frequency.
- Enabled Ged/Hal parameters for Mediatek.
- Set Snapdragon Devfreq to max frequency.
- Adjusted Ppm & Spm for Mediatek.
- Removed Uclamp in profiles.
- Removed Kernel Schedule in profiles.

### Stellar V7.5 (Eunoia) ###
Banner URL: ./assets/Stellar-V7.5-8.5.jpg
- Implemented Power Save Mode.
- Added Auto I/O Scheduler.
- Updated gamelist.
- Optimized tasks by PID for the daemon.
- Improved "Kill Logger & Trace" in WebUI.
- Streamlined core PID for game mode.
- Fixed bugs in WebUI and reduced visual padding.
- Added Toast notifications.
- Added prebuilt logic in Profiles.
- Added stellar_util function.
- Updated Bypass/Idle state support.
- Updated device spoofing for Samsung S24 Ultra.
- Used Uclamp schedule in profiles.
- Removed unstable 'perf_time_percent' to prevent shuttering.
- Replaced SF auto with SF latency.
- Added prebuilt Logic in WebUI.
- Various bug fixes & improvements.

### Stellar V7 (Elysium) ###
Banner URL: ./assets/Stellar-V7.5-8.5.jpg
- Full migration of the daemon from shell to Rust.
- New WebUI Interface.
- Logic refactor: Reduced overhead in process polling.
- Optimized pgrep PID handling with stricter regex matching.
- Better battery efficiency on the daemon.
- Merged SF 'Gaming & Latency' hooks into a single SF Auto.
- Dropped Unstable Profiles: 'mali-tweak', 'hmp-values', 'perf_cpu_time*'.
- Fixed OOM-kill edge case with preemptive throttling.
- Patched a leak in the daemon resource handler.
- Addressed random reboots on low-RAM devices (3GB)
- Daemon now survives hard LMK events.
- Adjusted OOM for running Pids (-1000) to prevent closing at panic RAM OOM.

### Stellar V6.7 ###
Banner URL: ./assets/Stellar-V6.5-6.7.jpg
- Added Preload (Only runs when a game is running).
- Optimized App Detection (20-30% less CPU usage).
- Fixed Self-boot/Random Boot issue on low-end devices when CPU usage hits 99%.
- Improved Focus Priority Handle to avoid child processing.
- Optimized logic in the Daemon.
- Initial preload version.

### Stellar V6.5 (Visoner) ###
Banner URL: ./assets/Stellar-V6.5-6.7.jpg
- Repaired logic service core from v6.2.
- Added Dex2oat option in WebUI.
- Added 2 options for Surfaceflinger in WebUI.
- Added game option in WebUI (only enables when a game is running).
- Improved game and normal profiles.
- Deleted system.prop to prevent bootloops.
- Added Bypass Charge State (if supported).
- Updated Spoof option in WebUI.
- Added GMS doze option in WebUI.
- Fixed Mobile Legends detection running in the background.
- Fixed random reboots caused by unmatched profiles.
- Removed save log button from WebUI, as logging is now automatic.

### Stellar V6.1 ###
Banner URL: ./assets/Stellar-V6.1.jpg
- Rebranded from Hiyorix to Stellar.
- Synced with webui encore 2.3 base.
- AI detects when a game is running.
- Auto profiles Governor.
- Added tweaks on WebUI: Logbuffer, Fstrim auto, Surfaceflinger, Device Spoofing, Disable CPU Limit.
- Improved disable logger functionality.
- Added RAM management prop from device port.
- Many other improvements.
