const { test, expect } = require('@playwright/test');
const { HOME_PAGE, waitForBootstrap } = require('./helpers');

test('header About dropdown opens and closes', async ({ page }) => {
  await page.goto(HOME_PAGE);
  await waitForBootstrap(page);
  const toggle = page.locator('#aLabel');
  const menu = toggle.locator('xpath=following-sibling::ul');
  await expect(menu).toBeHidden();
  await toggle.click();
  await expect(menu).toBeVisible();
  await expect(menu.getByRole('link', { name: 'Help' })).toBeVisible();
  // clicking elsewhere closes it
  await page.locator('body').click({ position: { x: 5, y: 400 } });
  await expect(menu).toBeHidden();
});

test('narrow viewport shows the compact "Lists" dropdown instead of button group', async ({ page }) => {
  await page.setViewportSize({ width: 500, height: 800 });
  await page.goto(HOME_PAGE);
  await waitForBootstrap(page);
  const toggle = page.locator('#hLabel');
  await expect(toggle).toBeVisible();
  await toggle.click();
  await expect(page.getByRole('link', { name: 'Package List' }).last()).toBeVisible();
});
