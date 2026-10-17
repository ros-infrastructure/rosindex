const { test, expect } = require('@playwright/test');
const { PACKAGE_PAGE, waitForBootstrap } = require('./helpers');

test('distro switch shows only the selected distro content', async ({ page }) => {
  await page.goto(PACKAGE_PAGE);
  await waitForBootstrap(page);
  await page.locator('#jazzy-option').click();
  await expect(page.locator('.distro-jazzy').first()).toBeVisible();
  await expect(page.locator('.distro-lyrical').first()).toBeHidden();
  await page.locator('#lyrical-option').click();
  await expect(page.locator('.distro-lyrical').first()).toBeVisible();
  await expect(page.locator('.distro-jazzy').first()).toBeHidden();
});

test('distro choice is stored in the rosdistro cookie', async ({ page, context }) => {
  await page.goto(PACKAGE_PAGE);
  await waitForBootstrap(page);
  await page.locator('#lyrical-option').click();
  const cookies = await context.cookies();
  expect(cookies.find((c) => c.name === 'rosdistro')?.value).toBe('lyrical');
});

test('"Older" dropdown opens', async ({ page }) => {
  await page.goto(PACKAGE_PAGE);
  await waitForBootstrap(page);
  await page.locator('#older-distro-button').click();
  await expect(page.locator('.older-distro-option').first()).toBeVisible();
});

test('unavailable "Older" distros are greyed out and cannot be selected', async ({ page, context }) => {
  await page.goto(PACKAGE_PAGE);
  await waitForBootstrap(page);
  await page.locator('#older-distro-button').click();
  const unavailable = page.locator('.older-distro-option.disabled a').first();
  const available = page.locator('.older-distro-option:not(.disabled) a').first();
  await expect(unavailable).toBeVisible();
  const color = (link) => link.evaluate((el) => getComputedStyle(el).color);
  expect(await color(unavailable)).not.toBe(await color(available));

  const distro = await unavailable.getAttribute('data');
  const urlBefore = page.url();
  // force: a real user's click lands on the item even though it ignores pointer events
  await unavailable.click({ force: true });
  expect(page.url()).toBe(urlBefore);
  const cookies = await context.cookies();
  expect(cookies.find((c) => c.name === 'rosdistro')?.value).not.toBe(distro);
});
