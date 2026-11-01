// Pages used by the tests. geometry2 is in repo_name_always in
// _config_devel.yml, so it is always in the test-build output. tf2_ros_py is
// ROS 2 only, so its "Older" dropdown has both available and unavailable distros.
exports.PACKAGE_PAGE = '/p/tf2_ros_py/';
exports.REPO_PAGE = '/r/geometry2/';
exports.HOME_PAGE = '/';

// Wait until jQuery and the Bootstrap components are loaded.
exports.waitForBootstrap = async (page) => {
  await page.waitForFunction(() => window.jQuery && window.bootstrap && window.bootstrap.Tab && window.bootstrap.Dropdown);
};

// Bootstrap hides inactive panes with display:none; "visible" is the
// behavioral check, independent of class names.
