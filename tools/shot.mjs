import { chromium } from 'playwright'

const EXE = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'
const out = process.argv[2] || 'shot.png'
const full = process.argv[3] === 'full'
const clicks = (process.argv[4] || '').split('|').filter(Boolean) // exact-text buttons to click

const browser = await chromium.launch({
  executablePath: EXE,
  args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--ignore-gpu-blocklist'],
})
const page = await browser.newPage({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 })
await page.goto('http://localhost:5173/', { waitUntil: 'networkidle' })
await page.waitForTimeout(1800)
for (const t of clicks) {
  try {
    await page.getByText(t, { exact: true }).first().click({ timeout: 3000 })
    await page.waitForTimeout(700)
  } catch (e) {
    console.log('click miss:', t)
  }
}
await page.waitForTimeout(1200)
await page.screenshot({ path: out, fullPage: full })
await browser.close()
console.log('wrote', out)
