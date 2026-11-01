const { test, expect } = require('@playwright/test');
const { HOME_PAGE, PACKAGE_PAGE } = require('./helpers');

// Breakpoints are explicit pixel widths so the same test can be run against a
// version of Bootstrap whose breakpoints differ (v3: 768/992/1200; v5: 576/768/992/1200/1400).
const widths = { xs: 500, sm: 800, md: 1000, lg: 1300 };

for (const [name, width] of Object.entries(widths)) {
  test(`header layout at ${name} (${width}px)`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(HOME_PAGE);
    const listsDropdown = page.locator('#hLabel');
    const listsButtons = page.getByRole('button', { name: 'Package List' }).or(page.getByRole('link', { name: 'Package List' })).first();
    if (width < 768) {
      await expect(listsDropdown).toBeVisible();
    } else {
      await expect(listsDropdown).toBeHidden();
      await expect(listsButtons).toBeVisible();
    }
    // No horizontal page scroll at any width.
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow).toBeLessThanOrEqual(1);
  });
}

// Package page content that changes with each upstream release. XPath on the
// visible labels keeps the masks independent of class names.
const volatile = (page) => [
  ...['Version', 'Last Updated'].map((label) =>
    page.locator(`xpath=//td[normalize-space()="${label}"]/following-sibling::td[1]`)),
  ...['Maintainers', 'README', 'CHANGELOG'].map((label) =>
    page.locator(`xpath=//div[normalize-space()="${label}"]/following-sibling::div[1]`)),
];

test('visual baseline: home and package page', { tag: '@visual' }, async ({ page }) => {
  for (const [name, width] of Object.entries(widths)) {
    await page.setViewportSize({ width, height: 900 });
    for (const [label, url] of [['home', HOME_PAGE], ['package', PACKAGE_PAGE]]) {
      await page.goto(url);
      await page.waitForLoadState('networkidle');
      await expect(page).toHaveScreenshot(`${label}-${name}.png`, {
        mask: [page.locator('time'), page.locator('[class*="count"]'), ...volatile(page)],
      });
    }
  }
});
