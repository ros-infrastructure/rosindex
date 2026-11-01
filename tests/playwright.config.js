// Serves the already-built static site in ../_site and runs browser tests against it.
// Build first with: docker/run.sh make test-build, then run docker/test.sh
const { defineConfig } = require('@playwright/test');

const port = process.env.PORT || 4010;

module.exports = defineConfig({
  testDir: './specs',
  timeout: 30000,
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    viewport: { width: 1280, height: 900 },
  },
  webServer: {
    // The server logs every request to stderr; keep that out of the test output.
    command: `mkdir -p test-results && python3 -m http.server ${port} --bind 127.0.0.1 --directory ../_site 2> test-results/http-server.log`,
    url: `http://127.0.0.1:${port}/`,
    reuseExistingServer: true,
  },
  // Behavior tests run in all three engines. Visual baselines (tagged @visual)
  // are recorded in Chromium only, since font rendering differs per engine.
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
    { name: 'firefox', use: { browserName: 'firefox' }, grepInvert: /@visual/ },
    { name: 'webkit', use: { browserName: 'webkit' }, grepInvert: /@visual/ },
  ],
  expect: {
    toHaveScreenshot: { maxDiffPixelRatio: 0.01 },
  },
  snapshotPathTemplate: '{testDir}/__screenshots__/{testFilePath}/{arg}{ext}',
});
