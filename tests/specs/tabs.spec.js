const { test, expect } = require('@playwright/test');
const { PACKAGE_PAGE, waitForBootstrap } = require('./helpers');

// The package page renders one set of tabs per distro. Use the first distro's tabs.
async function firstTabs(page) {
  await page.goto(PACKAGE_PAGE);
  await waitForBootstrap(page);
  const tabs = page.locator('ul[id$="-tabs"]').first();
  const distro = (await tabs.getAttribute('id')).replace(/-tabs$/, '');
  return { tabs, distro };
}

test('overview tab is shown by default', async ({ page }) => {
  const { distro } = await firstTabs(page);
  await expect(page.locator(`#${distro}-overview`)).toBeVisible();
  await expect(page.locator(`#${distro}-deps`)).toBeHidden();
});

test('clicking a tab shows its pane and hides the others', async ({ page }) => {
  const { tabs, distro } = await firstTabs(page);
  await tabs.locator(`a[href="#${distro}-deps"]`).click();
  await expect(page.locator(`#${distro}-deps`)).toBeVisible();
  await expect(page.locator(`#${distro}-overview`)).toBeHidden();
  await expect(tabs.locator(`a[href="#${distro}-deps"]`)).toHaveAttribute('aria-selected', 'true');
});

test('URL fragment opens the matching tab on load', async ({ page }) => {
  await page.goto(PACKAGE_PAGE);
  await waitForBootstrap(page);
  const distro = (await page.locator('ul[id$="-tabs"]').first().getAttribute('id')).replace(/-tabs$/, '');
  // a hash-only goto doesn't reload, so load a fresh page with the fragment
  await page.goto('about:blank');
  await page.goto(`${PACKAGE_PAGE}#${distro}-deps`);
  await waitForBootstrap(page);
  await expect(page.locator(`#${distro}-deps`)).toBeVisible();
});

test('clicking a tab updates the URL hash', async ({ page }) => {
  const { tabs, distro } = await firstTabs(page);
  await tabs.locator(`a[href="#${distro}-assets"]`).click();
  await expect(page).toHaveURL(new RegExp(`#${distro}-assets$`));
});
