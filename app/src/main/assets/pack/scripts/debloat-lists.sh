#!/system/bin/sh
# =============================================================================
#  debloat-lists.sh - listas de bloat por marca (so dados; a logica fica no
#  debloat.sh, que carrega este arquivo).
#
#  FONTE: banco de dados do Universal Android Debloater (UAD), projeto
#  Universal-Debloater-Alliance/universal-android-debloater-next-generation
#  (uad_lists.json). Daqui so entram pacotes com veredito "Recommended",
#  ou seja, remocao considerada segura pela comunidade, E que passam pelo
#  filtro de protecao abaixo (ver DBL_KEEP / DBL_NEVER).
#
#  Cada linha e "pacote|motivo". O motivo aparece na previa, para o usuario
#  saber POR QUE aquele app esta na lista.
#
#  REGRA DE OURO - nunca entram aqui: camera, galeria, telefone, mensagens,
#  contatos, relogio, calculadora, teclado, Bluetooth, NFC, Wi-Fi, launcher,
#  SystemUI, Settings, provedores do sistema, Google Play Services, biometria,
#  pagamento/NFC bancario, atualizacao do sistema, acessibilidade, pareamento
#  de relogio/fone, e qualquer pacote marcado "Unsafe" pelo UAD.
# =============================================================================

# --- Universal (qualquer marca) (25 pacotes) ---
DBL_UNIVERSAL='com.facebook.katana|rede social
com.facebook.orca|rede social
com.facebook.appmanager|rede social
com.facebook.services|rede social
com.facebook.system|rede social
com.netflix.partner.activation|app de loja/operadora
com.amazon.appmanager|app de fábrica sem uso
com.amazon.mShop.android.shopping|app de loja/operadora
com.amazon.avod.thirdpartyclient|app de fábrica sem uso
com.amazon.mp3|app de fábrica sem uso
com.amazon.kindle|app de fábrica sem uso
com.microsoft.skydrive|escritório/nuvem
com.microsoft.office.outlook|escritório/nuvem
com.microsoft.office.word|escritório/nuvem
com.linkedin.android|rede social
com.booking|app de fábrica sem uso
com.ebay.mobile|app de fábrica sem uso
com.tripadvisor.tripadvisor|app de fábrica sem uso
com.contextlogic.wish|app de fábrica sem uso
com.google.android.apps.tachyon|app de fábrica sem uso
com.google.android.apps.magazines|app de fábrica sem uso
com.google.android.apps.subscriptions.red|app de fábrica sem uso
com.google.android.apps.nbu.files|app de fábrica sem uso
com.gameloft.android.ANMP.GloftA9HM|jogo pré-instalado
com.opera.preinstall|navegador extra'

# --- Samsung (40 pacotes) ---
DBL_SAMSUNG='com.samsung.android.airtel.stubapp|app de loja/operadora
com.samsung.android.drivelink.stub|app de loja/operadora
com.samsung.android.ststub|app de loja/operadora
com.samsung.carrier.logcollector|app de loja/operadora
com.samsung.preloadapp|app de loja/operadora
com.sec.android.stub.paywithpaypal|app de loja/operadora
com.samsung.android.game.gametools|jogo pré-instalado
com.samsung.android.game.gos|jogo pré-instalado
com.samsung.android.gametuner.thin|jogo pré-instalado
com.sec.android.app.gamehub|jogo pré-instalado
com.samsung.android.app.sketchbook|vídeo/streaming
com.samsung.android.app.withtv|vídeo/streaming
com.samsung.attvvm|vídeo/streaming
com.samsung.mobiletv|vídeo/streaming
com.samsung.sec.mtv|vídeo/streaming
com.sec.android.app.withtv|vídeo/streaming
com.samsung.android.app.spage|assistente/IA redundante
com.samsung.android.bixby.agent|assistente/IA redundante
com.samsung.android.bixby.agent.dummy|assistente/IA redundante
com.samsung.android.bixby.es.globalaction|assistente/IA redundante
com.samsung.android.bixby.service|assistente/IA redundante
com.samsung.android.bixby.voiceinput|assistente/IA redundante
com.samsung.android.bixby.wakeup|assistente/IA redundante
com.samsung.android.bixbyhelper|assistente/IA redundante
com.samsung.android.bixbytouch|assistente/IA redundante
com.samsung.android.voicewakeup|assistente/IA redundante
com.samsung.hongbaoassistant|assistente/IA redundante
com.samsung.voiceserviceplatform|assistente/IA redundante
com.sec.android.app.voicenote|assistente/IA redundante
com.samsung.android.app.tips|recurso extra (AR/emoji/tutorial)
com.samsung.android.ardrawing|recurso extra (AR/emoji/tutorial)
com.samsung.android.aremoji|recurso extra (AR/emoji/tutorial)
com.samsung.android.aremojieditor|recurso extra (AR/emoji/tutorial)
com.samsung.android.arzone|recurso extra (AR/emoji/tutorial)
com.samsung.android.livestickers|recurso extra (AR/emoji/tutorial)
com.samsung.android.stickercenter|recurso extra (AR/emoji/tutorial)
com.samsung.android.stickerplugin|recurso extra (AR/emoji/tutorial)
com.samsung.helphub|recurso extra (AR/emoji/tutorial)
com.sec.android.app.tourviewer|recurso extra (AR/emoji/tutorial)
com.sec.android.mimage.avatarstickers|recurso extra (AR/emoji/tutorial)'

# --- Xiaomi / Redmi / Poco (40 pacotes) ---
DBL_XIAOMI='com.miui.analytics|anúncios/telemetria
com.miui.bugreport|anúncios/telemetria
com.miui.klo.bugreport|anúncios/telemetria
com.miui.systemAdSolution|anúncios/telemetria
com.miui.tv.analytics|anúncios/telemetria
com.mi.global.bbs|app de loja/operadora
com.mi.global.pocobbs|app de loja/operadora
com.mi.global.pocostore|app de loja/operadora
com.mi.global.shop|app de loja/operadora
com.miui.carrierinstructions|app de loja/operadora
com.miui.enbbs|app de loja/operadora
com.xiaomi.shop|app de loja/operadora
com.xiaomi.gamecenter|jogo pré-instalado
com.xiaomi.gamecenter.sdk.service|jogo pré-instalado
com.xiaomi.migameservice|jogo pré-instalado
com.mi.android.globalminusscreen|assistente/IA redundante
com.mi.android.globalpersonalassistant|assistente/IA redundante
com.mi.globalminusscreen|assistente/IA redundante
com.mi.liveassistant|assistente/IA redundante
com.miui.core.internal.assistant|assistente/IA redundante
com.miui.personalassistant|assistente/IA redundante
com.miui.thirdappassistant|assistente/IA redundante
com.miui.touchassistant|assistente/IA redundante
com.miui.voiceassist|assistente/IA redundante
com.miui.voicetrigger|assistente/IA redundante
com.xiaomi.oobhelper|recurso extra (AR/emoji/tutorial)
com.mi.globalbrowser|navegador extra
com.mi.AutoTest|app de fábrica sem uso
com.mi.appfinder|app de fábrica sem uso
com.mi.emapal|app de fábrica sem uso
com.mi.globalTrendNews|app de fábrica sem uso
com.mi.webkit.core|app de fábrica sem uso
com.miui.antispam|app de fábrica sem uso
com.miui.carlink|app de fábrica sem uso
com.miui.catcherpatch|app de fábrica sem uso
com.miui.cit|app de fábrica sem uso
com.miui.cleaner|app de fábrica sem uso
com.miui.cleanmaster|app de fábrica sem uso
com.miui.compass|app de fábrica sem uso
com.miui.contentcatcher|app de fábrica sem uso'

# --- Motorola (40 pacotes) ---
DBL_MOTOROLA='com.motorola.iqimotmetrics|anúncios/telemetria
com.motorola.demo|recurso extra (AR/emoji/tutorial)
com.motorola.demo.env|recurso extra (AR/emoji/tutorial)
com.motorola.help|recurso extra (AR/emoji/tutorial)
com.motorola.help.extlog|recurso extra (AR/emoji/tutorial)
com.motorola.mototour|recurso extra (AR/emoji/tutorial)
com.motorola.android.nativedropboxagent|escritório/nuvem
com.motorola.aiservices|app de fábrica sem uso
com.motorola.android.jvtcmd|app de fábrica sem uso
com.motorola.brapps|app de fábrica sem uso
com.motorola.bug2go|app de fábrica sem uso
com.motorola.callredirectionservice|app de fábrica sem uso
com.motorola.ccc.mainplm|app de fábrica sem uso
com.motorola.ccc.notification|app de fábrica sem uso
com.motorola.dciservice|app de fábrica sem uso
com.motorola.discovery|app de fábrica sem uso
com.motorola.easyprefix|app de fábrica sem uso
com.motorola.email|app de fábrica sem uso
com.motorola.genie|app de fábrica sem uso
com.motorola.gesture|app de fábrica sem uso
com.motorola.invisiblenet|app de fábrica sem uso
com.motorola.lifetimedata|app de fábrica sem uso
com.motorola.mobiledesktop|app de fábrica sem uso
com.motorola.mobiledesktop.core|app de fábrica sem uso
com.motorola.moto|app de fábrica sem uso
com.motorola.motocare|app de fábrica sem uso
com.motorola.motocare.internal|app de fábrica sem uso
com.motorola.motocit|app de fábrica sem uso
com.motorola.motodisplay|app de fábrica sem uso
com.motorola.omadm.service|app de fábrica sem uso
com.motorola.omadm.usc|app de fábrica sem uso
com.motorola.omadm.vzw|app de fábrica sem uso
com.motorola.paks|app de fábrica sem uso
com.motorola.paks.notification|app de fábrica sem uso
com.motorola.programmenu|app de fábrica sem uso
com.motorola.revoker.services|app de fábrica sem uso
com.motorola.slpc_sys|app de fábrica sem uso
com.motorola.spaces|app de fábrica sem uso
com.motorola.systemserver|app de fábrica sem uso
com.motorola.timeweatherwidget|app de fábrica sem uso'

# --- OnePlus / Oppo (40 pacotes) ---
DBL_ONEPLUS='com.oneplus.opbugreportlite|anúncios/telemetria
com.oplus.statistics.rom|anúncios/telemetria
com.oneplus.store|app de loja/operadora
com.oppo.partnerbrowsercustomizations|app de loja/operadora
com.oneplus.gamespace|jogo pré-instalado
com.oplus.games|jogo pré-instalado
com.heytap.quicksearchbox|vídeo/streaming
com.oplus.crashbox|vídeo/streaming
com.oppo.quicksearchbox|vídeo/streaming
com.oplus.ovoicemanager|assistente/IA redundante
com.oplus.ovoicemanager.wakeup|assistente/IA redundante
com.oppo.ovoicemanager|assistente/IA redundante
com.oplus.sauhelper|recurso extra (AR/emoji/tutorial)
com.heytap.browser|navegador extra
com.oppo.operationManual|navegador extra
com.heytap.colorfulengine|app de fábrica sem uso
com.heytap.datamigration|app de fábrica sem uso
com.heytap.habit.analysis|app de fábrica sem uso
com.heytap.market|app de fábrica sem uso
com.heytap.mcs|app de fábrica sem uso
com.heytap.openid|app de fábrica sem uso
com.heytap.pictorial|app de fábrica sem uso
com.heytap.speechassist|app de fábrica sem uso
com.heytap.yoli|app de fábrica sem uso
com.oneplus.aod|app de fábrica sem uso
com.oneplus.brickmode|app de fábrica sem uso
com.oneplus.bttestmode|app de fábrica sem uso
com.oneplus.card|app de fábrica sem uso
com.oneplus.chargingpilar|app de fábrica sem uso
com.oneplus.dm|app de fábrica sem uso
com.oneplus.faceunlock|app de fábrica sem uso
com.oneplus.factorymode|app de fábrica sem uso
com.oneplus.factorymode.specialtest|app de fábrica sem uso
com.oneplus.iconpack.oneplush2|app de fábrica sem uso
com.oneplus.iconpack.onepluso2|app de fábrica sem uso
com.oneplus.ifaaservice|app de fábrica sem uso
com.oneplus.membership|app de fábrica sem uso
com.oneplus.minidumpoptimization|app de fábrica sem uso
com.oneplus.opshelf|app de fábrica sem uso
com.oneplus.opsports|app de fábrica sem uso'

# --- Realme (40 pacotes) ---
DBL_REALME='com.coloros.avastofferwall|app de loja/operadora
com.coloros.gamespace|jogo pré-instalado
com.coloros.gamespaceui|jogo pré-instalado
com.coloros.floatassistant|assistente/IA redundante
com.coloros.operationtips|recurso extra (AR/emoji/tutorial)
com.coloros.sauhelper|recurso extra (AR/emoji/tutorial)
com.coloros.operationManual|navegador extra
com.coloros.apprecover|app de fábrica sem uso
com.coloros.childrenspace|app de fábrica sem uso
com.coloros.codebook|app de fábrica sem uso
com.coloros.colordirectservice|app de fábrica sem uso
com.coloros.colorfilestand|app de fábrica sem uso
com.coloros.directui|app de fábrica sem uso
com.coloros.dirrecord|app de fábrica sem uso
com.coloros.exserviceui|app de fábrica sem uso
com.coloros.eyeprotect|app de fábrica sem uso
com.coloros.feedback|app de fábrica sem uso
com.coloros.focusmode|app de fábrica sem uso
com.coloros.gesture|app de fábrica sem uso
com.coloros.karaoke|app de fábrica sem uso
com.coloros.logkit|app de fábrica sem uso
com.coloros.logkit.plugin.upload|app de fábrica sem uso
com.coloros.mapcom.frame|app de fábrica sem uso
com.coloros.mcs|app de fábrica sem uso
com.coloros.ocrscanner|app de fábrica sem uso
com.coloros.ocrservice|app de fábrica sem uso
com.coloros.ocs.opencapabilityservice|app de fábrica sem uso
com.coloros.onekeylockscreen|app de fábrica sem uso
com.coloros.oppomultiapp|app de fábrica sem uso
com.coloros.prome.service|app de fábrica sem uso
com.coloros.regservice|app de fábrica sem uso
com.coloros.remoteguardservice|app de fábrica sem uso
com.coloros.safecenter.config_plugin|app de fábrica sem uso
com.coloros.safesdkproxy|app de fábrica sem uso
com.coloros.scenemode|app de fábrica sem uso
com.coloros.sceneservice|app de fábrica sem uso
com.coloros.securepay|app de fábrica sem uso
com.coloros.sharescreen|app de fábrica sem uso
com.coloros.smartdrive|app de fábrica sem uso
com.coloros.smartlock|app de fábrica sem uso'

# --- Vivo / iQOO (40 pacotes) ---
DBL_VIVO='com.vivo.appstore|app de loja/operadora
com.vivo.gamewatch|jogo pré-instalado
com.vivo.assistant|assistente/IA redundante
com.vivo.assistantfunction|assistente/IA redundante
com.vivo.voicewakeup|assistente/IA redundante
com.vivo.desktopstickers|recurso extra (AR/emoji/tutorial)
com.vivo.browser|navegador extra
com.bbk.SuperPowerSave|app de fábrica sem uso
com.bbk.iqoo.logsystem|app de fábrica sem uso
com.bbk.photoframewidget|app de fábrica sem uso
com.iqoo.aftersale.engineermode|app de fábrica sem uso
com.iqoo.engineermode|app de fábrica sem uso
com.iqoo.user.engineermode|app de fábrica sem uso
com.iqoo.website|app de fábrica sem uso
com.vivo.SmartKey|app de fábrica sem uso
com.vivo.abe|app de fábrica sem uso
com.vivo.bsptest|app de fábrica sem uso
com.vivo.compass|app de fábrica sem uso
com.vivo.contentcatcher|app de fábrica sem uso
com.vivo.cota|app de fábrica sem uso
com.vivo.crontab|app de fábrica sem uso
com.vivo.daemonService|app de fábrica sem uso
com.vivo.devicereg|app de fábrica sem uso
com.vivo.doubleinstance|app de fábrica sem uso
com.vivo.dream.weather|app de fábrica sem uso
com.vivo.easyshare|app de fábrica sem uso
com.vivo.epm|app de fábrica sem uso
com.vivo.ewarranty|app de fábrica sem uso
com.vivo.favorite|app de fábrica sem uso
com.vivo.feedback|app de fábrica sem uso
com.vivo.floatingball|app de fábrica sem uso
com.vivo.fuelsummary|app de fábrica sem uso
com.vivo.globalanimation|app de fábrica sem uso
com.vivo.globalanimation.resources|app de fábrica sem uso
com.vivo.globalsearch|app de fábrica sem uso
com.vivo.heduohao|app de fábrica sem uso
com.vivo.iotserver|app de fábrica sem uso
com.vivo.magazine|app de fábrica sem uso
com.vivo.minscreen|app de fábrica sem uso
com.vivo.monochromeicons|app de fábrica sem uso'

# --- Huawei / Honor (40 pacotes) ---
DBL_HUAWEI='com.huawei.himovie.partner1|app de loja/operadora
com.huawei.himovie.partner2|app de loja/operadora
com.hihonor.gameassistant|jogo pré-instalado
com.huawei.gameassistant|jogo pré-instalado
com.huawei.gamebox|jogo pré-instalado
com.hihonor.assistant|assistente/IA redundante
com.hihonor.pcassistant|assistente/IA redundante
com.huawei.hiassistantoversea|assistente/IA redundante
com.huawei.pcassistant|assistente/IA redundante
com.huawei.vassistant|assistente/IA redundante
com.huawei.android.tips|recurso extra (AR/emoji/tutorial)
com.huawei.ridemode|recurso extra (AR/emoji/tutorial)
com.huawei.tips|recurso extra (AR/emoji/tutorial)
com.huawei.tipsove|recurso extra (AR/emoji/tutorial)
com.huawei.browser|navegador extra
com.hihonor.remotepassword|escritório/nuvem
com.huawei.remotepassword|escritório/nuvem
com.hihonor.aipluginengine|app de fábrica sem uso
com.hihonor.android.FloatTasks|app de fábrica sem uso
com.hihonor.android.chr|app de fábrica sem uso
com.hihonor.android.hnupgradeguide|app de fábrica sem uso
com.hihonor.android.instantshare|app de fábrica sem uso
com.hihonor.android.projectmenu|app de fábrica sem uso
com.hihonor.appmarket|app de fábrica sem uso
com.hihonor.autoinstallapkfrommcc|app de fábrica sem uso
com.hihonor.awareness|app de fábrica sem uso
com.hihonor.behaviorauth|app de fábrica sem uso
com.hihonor.collectcenter|app de fábrica sem uso
com.hihonor.compass|app de fábrica sem uso
com.hihonor.detectrepair|app de fábrica sem uso
com.hihonor.filemanager|app de fábrica sem uso
com.hihonor.hiview|app de fábrica sem uso
com.hihonor.hnpanpayservice|app de fábrica sem uso
com.hihonor.hnstartupguide|app de fábrica sem uso
com.hihonor.iconnect|app de fábrica sem uso
com.hihonor.lens|app de fábrica sem uso
com.hihonor.linktowindowsservice|app de fábrica sem uso
com.hihonor.magazine|app de fábrica sem uso
com.hihonor.mmitest|app de fábrica sem uso
com.hihonor.notepad|app de fábrica sem uso'

# --- Asus (40 pacotes) ---
DBL_ASUS='com.asus.inadvertentTouch|anúncios/telemetria
com.asus.livedemoservice|recurso extra (AR/emoji/tutorial)
com.asus.tips|recurso extra (AR/emoji/tutorial)
com.asus.alwayson|app de fábrica sem uso
com.asus.atd.smmitest|app de fábrica sem uso
com.asus.ephotoburst|app de fábrica sem uso
com.asus.ia.asusapp|app de fábrica sem uso
com.asus.imagesearch|app de fábrica sem uso
com.asus.ims.benchmarkblocker|app de fábrica sem uso
com.asus.ims.brightnessservice|app de fábrica sem uso
com.asus.ims.configmanager|app de fábrica sem uso
com.asus.ims.devicepolicymanager|app de fábrica sem uso
com.asus.ims.evtlog|app de fábrica sem uso
com.asus.ims.extdispctrl|app de fábrica sem uso
com.asus.ims.forcedark|app de fábrica sem uso
com.asus.ims.freeform|app de fábrica sem uso
com.asus.ims.observer|app de fábrica sem uso
com.asus.ims.phykeyctrl|app de fábrica sem uso
com.asus.ims.pointerproxy|app de fábrica sem uso
com.asus.ims.powerctrl|app de fábrica sem uso
com.asus.ims.rogproxy|app de fábrica sem uso
com.asus.ims.smartread|app de fábrica sem uso
com.asus.ims.twinapps|app de fábrica sem uso
com.asus.ims.watermark|app de fábrica sem uso
com.asus.key_status|app de fábrica sem uso
com.asus.loguploader|app de fábrica sem uso
com.asus.loguploaderproxy|app de fábrica sem uso
com.asus.openbeta2|app de fábrica sem uso
com.asus.sarprotection|app de fábrica sem uso
com.asus.smartcover|app de fábrica sem uso
com.asus.smartkey|app de fábrica sem uso
com.asus.smartreading|app de fábrica sem uso
com.asus.splendid|app de fábrica sem uso
com.asus.stitchimage.service|app de fábrica sem uso
com.asus.sysmonitor|app de fábrica sem uso
com.asus.taskwidget|app de fábrica sem uso
com.asus.twinapps|app de fábrica sem uso
com.asus.twinappsservice|app de fábrica sem uso
com.asus.userfeedback|app de fábrica sem uso
com.asus.weathertime|app de fábrica sem uso'

# --- Sony (8 pacotes) ---
DBL_SONY='com.sony.dtv.promos|app de loja/operadora
com.sony.dtv.livingfit|vídeo/streaming
com.sony.dtv.notificationcenter|vídeo/streaming
com.sony.dtv.recapp|vídeo/streaming
com.sony.dtv.seeds.iot|vídeo/streaming
com.sony.dtv.smarthelp|vídeo/streaming
com.sony.dtv.sonyselect|vídeo/streaming
com.sony.dtv.timers|vídeo/streaming'

# --- LG (40 pacotes) ---
DBL_LG='com.lge.lifetracker|anúncios/telemetria
com.lge.penprime|vídeo/streaming
com.lge.snappage|rede social
com.lge.voicecare|assistente/IA redundante
com.lge.qhelp|recurso extra (AR/emoji/tutorial)
com.lge.qhelp.application|recurso extra (AR/emoji/tutorial)
com.lge.LGSetupView|app de fábrica sem uso
com.lge.animal.resource|app de fábrica sem uso
com.lge.appbox.client|app de fábrica sem uso
com.lge.appwidget.runningtaskbar|app de fábrica sem uso
com.lge.autosimlockservice|app de fábrica sem uso
com.lge.bnr|app de fábrica sem uso
com.lge.calligraphydictionary|app de fábrica sem uso
com.lge.cic.eden.service|app de fábrica sem uso
com.lge.cinemagraph|app de fábrica sem uso
com.lge.cota.blm.sf340_enabler|app de fábrica sem uso
com.lge.covertools|app de fábrica sem uso
com.lge.drive.activator|app de fábrica sem uso
com.lge.dualscreenfirmware|app de fábrica sem uso
com.lge.effect|app de fábrica sem uso
com.lge.eltest|app de fábrica sem uso
com.lge.email|app de fábrica sem uso
com.lge.floatingbar|app de fábrica sem uso
com.lge.friendsmanager|app de fábrica sem uso
com.lge.gcuv|app de fábrica sem uso
com.lge.gestureanswering|app de fábrica sem uso
com.lge.gnss.airtest|app de fábrica sem uso
com.lge.gnsslogcat|app de fábrica sem uso
com.lge.gnsslogsetting|app de fábrica sem uso
com.lge.gnsspostest|app de fábrica sem uso
com.lge.gnsstest|app de fábrica sem uso
com.lge.ia.task.incalagent|app de fábrica sem uso
com.lge.ia.task.informant|app de fábrica sem uso
com.lge.ia.task.smartcare|app de fábrica sem uso
com.lge.ia.task.smartsetting|app de fábrica sem uso
com.lge.iftttmanager|app de fábrica sem uso
com.lge.ime.solution.handwriting|app de fábrica sem uso
com.lge.ims.chatbotinfoprovider|app de fábrica sem uso
com.lge.ims.rcsprovider|app de fábrica sem uso
com.lge.imsvt|app de fábrica sem uso'

# --- Tecno / Infinix / itel (40 pacotes) ---
DBL_TRANSSION='com.transsion.statisticalsales|anúncios/telemetria
com.transsion.aivoiceassistant|assistente/IA redundante
com.transsion.kolun.assistant|assistente/IA redundante
com.transsion.agingfunction|recurso extra (AR/emoji/tutorial)
com.transsion.avatar|recurso extra (AR/emoji/tutorial)
com.transsion.tips|recurso extra (AR/emoji/tutorial)
com.infinix.xshare|app de fábrica sem uso
com.transsion.aftersalecalibrationtool|app de fábrica sem uso
com.transsion.aod|app de fábrica sem uso
com.transsion.auto|app de fábrica sem uso
com.transsion.autotest.factory|app de fábrica sem uso
com.transsion.beezedit|app de fábrica sem uso
com.transsion.carlcare|app de fábrica sem uso
com.transsion.childmode|app de fábrica sem uso
com.transsion.chromecustomization|app de fábrica sem uso
com.transsion.datatransfer|app de fábrica sem uso
com.transsion.deadcycletest|app de fábrica sem uso
com.transsion.dualapp|app de fábrica sem uso
com.transsion.filemanagerx|app de fábrica sem uso
com.transsion.hamal|app de fábrica sem uso
com.transsion.hiparty|app de fábrica sem uso
com.transsion.infinix.xclub|app de fábrica sem uso
com.transsion.iotservice|app de fábrica sem uso
com.transsion.kolun.aiservice|app de fábrica sem uso
com.transsion.letswitch|app de fábrica sem uso
com.transsion.magazineservice.hios|app de fábrica sem uso
com.transsion.magazineservice.xos|app de fábrica sem uso
com.transsion.magicshow|app de fábrica sem uso
com.transsion.manualguide|app de fábrica sem uso
com.transsion.mol|app de fábrica sem uso
com.transsion.nephilim|app de fábrica sem uso
com.transsion.netphilim|app de fábrica sem uso
com.transsion.notebook|app de fábrica sem uso
com.transsion.phoenix|app de fábrica sem uso
com.transsion.plat.appupdate|app de fábrica sem uso
com.transsion.quicktools|app de fábrica sem uso
com.transsion.repaircard|app de fábrica sem uso
com.transsion.scanningrecharger|app de fábrica sem uso
com.transsion.sk|app de fábrica sem uso
com.transsion.smartpanel|app de fábrica sem uso'

# --- Protecao em tempo de execucao (defesa em profundidade) -------------------
# Mesmo que algo perigoso escapasse das listas, o debloat.sh recusa o pacote.
DBL_KEEP="talkback accessib accesscontrol assistantmenu voiceaccess switchaccess
accessory watchmanager beansmgr safiletransfer buds gear wearable companion
adaptivebrightness autobrightness inputevent inputmethod keyboard honeyboard
authfw account sync payment wallet tsm uicc esim knox security findmy
aircommand spen snote notes memo reminder calendar clock calculator contacts dialer
camera gallery photos media player recorder soundrecorder wallpaper theme overlay
launcher home touchwiz systemui settings providers phone telecom telephony mms sms messag
shell bluetooth nfc documentsui keychain certinstaller packageinstaller permissioncontroller
setupwizard provision simtoolkit keyguard biometr fingerprint fpstouch fpc goodix synaptics credential framework
gms gsf vending wifi audio codec vold keystore appops deviceid drm widevine
health samsungpay dex smartswitch print spooler emergency safety
radio modem volume ptt dmb svoice locat diag vpn gatekeeper
updater installer fota devicemanagement enterprise mdm cloud backup
cast mirror usb stylus rro mot5gmod"

# Pacotes que NUNCA podem ser removidos, mesmo se aparecerem numa lista.
DBL_NEVER="android com.android.systemui com.android.settings com.android.shell
com.android.providers.media com.android.providers.contacts com.android.providers.telephony
com.android.providers.downloads com.android.providers.calendar com.android.providers.settings
com.android.phone com.android.server.telecom com.android.bluetooth com.android.nfc
com.android.keychain com.android.certinstaller com.android.documentsui com.android.vending
com.google.android.gms com.google.android.gsf com.android.launcher3 com.android.inputmethod.latin"
