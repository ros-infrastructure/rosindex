const { test, expect } = require('@playwright/test');
const { waitForBootstrap } = require('./helpers');

const PACKAGE_LIST = '/?search_packages=true';

const columnHeader = (page, field) => page.locator(`.tabulator-col[tabulator-field="${field}"]`);

async function openChooser(page) {
  await page.goto(PACKAGE_LIST);
  await waitForBootstrap(page);
  await expect(columnHeader(page, 'description')).toBeVisible();
  await page.locator('#column-chooser-button').click();
  const menu = page.locator('#column-chooser');
  await expect(menu).toBeVisible();
  return menu;
}

test('Columns menu shows default columns and hides optional ones', async ({ page }) => {
  const menu = await openChooser(page);
  await expect(menu.getByRole('checkbox', { name: 'Description' })).toBeChecked();
  await expect(menu.getByRole('checkbox', { name: 'Org' })).toBeChecked();
  await expect(menu.getByRole('checkbox', { name: 'Version' })).not.toBeChecked();
  await expect(menu.getByRole('checkbox', { name: 'Core' })).not.toBeChecked();
  await expect(columnHeader(page, 'org')).toBeVisible();
  await expect(columnHeader(page, 'version')).toBeHidden();
  await expect(columnHeader(page, 'core')).toBeHidden();
});

test('toggling a column shows it, keeps the menu open and is remembered', async ({ page }) => {
  const menu = await openChooser(page);
  await menu.getByRole('checkbox', { name: 'Version' }).check();
  await expect(columnHeader(page, 'version')).toBeVisible();
  await menu.getByRole('checkbox', { name: 'Description' }).uncheck();
  await expect(columnHeader(page, 'description')).toBeHidden();
  await expect(menu).toBeVisible();

  await page.reload();
  await waitForBootstrap(page);
  await expect(columnHeader(page, 'version')).toBeVisible();
  await expect(columnHeader(page, 'description')).toBeHidden();
});

test('Reset to defaults restores the default columns', async ({ page }) => {
  const menu = await openChooser(page);
  await menu.getByRole('checkbox', { name: 'Version' }).check();
  await expect(columnHeader(page, 'version')).toBeVisible();
  await menu.getByRole('link', { name: 'Reset to defaults' }).click();
  await expect(columnHeader(page, 'version')).toBeHidden();
  await expect(menu.getByRole('checkbox', { name: 'Version' })).not.toBeChecked();
});

test('clicking outside closes the Columns menu', async ({ page }) => {
  const menu = await openChooser(page);
  await page.locator('body').click({ position: { x: 5, y: 5 } });
  await expect(menu).toBeHidden();
});
