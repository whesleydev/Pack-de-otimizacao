import { exec, fullScreen, toast } from "https://cdn.jsdelivr.net/npm/kernelsu@1.0.6/+esm";

// ID elementFromPoint
const BtnOn = document.getElementById('BtnOnSmart')
const BtnOff = document.getElementById('BtnOffSmart')
const SliderDex = document.getElementById('SlideDex')
const BtnSave = document.getElementById('BtnSaveId')

async function getDexActive(uiElement) {
  try {
    const { stdout: GetCheckDex } = await exec(
      `
      settings get global dex_veulexier_enable
      `  
    )
    GetCheckDex.trim() == 'true' ? uiElement.checked = true : uiElement.checked = false
  } catch (e) {
    console.log(e)
  }
}

async function getCurrentTimeCustom() {
  try {
    const {stdout: GetCurrentTime} = await exec(
      `
      settings get global custom_time_veu
      `
    )
    GetCurrentTime.trim() !== 'null' ? document.getElementById('current-time-id').textContent = GetCurrentTime.trim() : document.getElementById('current-time-id').textContent = 'Not Set Custom'
  } catch (e) {
    console.log(e)
  }
}

async function getActiveEngine() {
  try {
    const { stdout: GetActiveEngine } = await exec(
      `
      pgrep -f lex.sh | wc -l
      `
    )
    const StsEngine = document.getElementById('sts-engine-id')
    GetActiveEngine.trim() == '2' ? StsEngine.textContent = 'Actived' : StsEngine.textContent = 'Deactived'
  } catch (e) {
    console.log(e)
  }
}

BtnOn.addEventListener('click', async () => {
  try {
    const { stdout: GetActiveEngine } = await exec(
      `
      pgrep -f lex.sh | wc -l
      `
    )
    if (GetActiveEngine.trim() == '2') {
      toast('Smart Cache Cleaner Sudah Active')
    } else {
      await exec('nohub /data/data/com.android.shell/AxManager/plugins/veulex/system/lex.sh >/dev/null 2>&1 &')
      await getActiveEngine()
      toast('Smart Cache Cleaner Activated Succesfuly')
    }
  } catch (e) {
    console.log(e)
  }
})
BtnOff.addEventListener('click', async () => {
  try {
    const { stdout: GetActiveEngine } = await exec(
      `
      pgrep -f lex.sh | wc -l
      `
    )
    if (GetActiveEngine.trim() !== '2') {
      toast('Smart Cache Cleaner Sudah Di Non Active Kan')
    } else {
      await exec(
        `
        pid=$(pgrep -f lex.sh)
        kill -9 $pid
        kill -9 $pid
        `
      )
      await getActiveEngine()
      toast('Smart Cache Cleaner Deactivated Succesfuly')
    }
  } catch (e) {
    console.log(e)
  }
});

SliderDex.addEventListener("change", async () => {
  try {
    if(SliderDex.checked) {
      await exec('settings put global dex_veulexier_enable true')
      toast('Dex2oat Compiler Active')
    } else {
      await exec('settings put global dex_veulexier_enable false')
      toast('Dex2oat Compiler Deactivated')
    }
  } catch (e) {
    console.log(e)
  }
})

BtnSave.addEventListener("click", async () => {
  try {
    exec(
      `
      settings put global custom_time_veu ${document.getElementById('time-value-id').value}
      `  
    )
    await getCurrentTimeCustom()
    window.location.reload();
    toast(`Change Custom Time Smart VeuLexier Succesfuly`)
  } catch (e) {
    console.log(e)
  }
})

document.addEventListener("DOMContentLoaded", async () => {
  try {
    await getDexActive(SliderDex)
    await getCurrentTimeCustom()
    await getActiveEngine()
  } catch (e) {} finally {
    document.getElementById('loader-blocking').style.display = 'none';
  }
})