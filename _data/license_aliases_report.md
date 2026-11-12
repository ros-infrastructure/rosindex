# License strings in ROS 2 Jazzy package.xml files

Scanned `/srv/repos/jazzy` on 2026-10-17: **831 repositories, 2942 packages** (every directory containing a `package.xml`, skipping hidden directories; 34 of them sit in `COLCON_IGNORE`/`AMENT_IGNORE`/`CATKIN_IGNORE` directories and are included anyway). Packages with the same name in more than one repo (e.g. `_release` copies) are counted separately. Compared against the SPDX License List 3.29.0.

## Summary

| | Count |
|---|---:|
| Packages | 2942 |
| Packages with more than one `<license>` tag | 85 |
| Packages with no `<license>` tag | 0 |
| Distinct license strings | 77 |
| … that are current SPDX ids | 24 |
| … that are deprecated SPDX ids | 3 |
| … that are not SPDX ids | 50 |
| Packages whose licenses are all valid SPDX today | 1125 (38%) |
| Packages whose licenses are all valid SPDX after aliasing | 2940 (99.9%) |

Packages are counted once per distinct string they use. The biggest wins are `Apache License 2.0` (788 packages), `BSD` (634) and `Apache 2.0` (223).

## How the aliases were chosen

- **Evidence.** For every package using a non-SPDX string, the nearest `LICENSE*`/`COPYING*`/`LICENCE*` files (package directory, then parents up to the repo root, plus any `<license file="...">`) were classified by their text. For GPL-family strings, source file headers in the package were also checked for "or any later version".
- **Versioned GPL-family strings without "+" or "or later"** (`GPLv3`, `LGPLv3`, ...) are mapped to `-only`. That is what the string says, and it is how SPDX defines its deprecated bare ids (`GPL-3.0` = `GPL-3.0-only`). Where headers say "or later" the package is under-declaring, which should be fixed upstream, not by the alias.
- **Unversioned GPL/LGPL** are mapped literally (the license lets you pick any version, so `GPL-1.0-or-later` / `LGPL-2.0-or-later`). Low confidence: the packages actually ship different versions.
- **`BSD`** is mapped to `BSD-3-Clause`, the ROS convention, backed by the license files (table below).
- **No SPDX id exists** for public domain or proprietary terms, so these get `LicenseRef-` ids, which are valid in SPDX expressions.
- Confidence: **high** = only the spelling differs; **medium** = a conventional reading of an ambiguous string; **low** = the string does not have enough information and the packages disagree.

## Proposed aliases

| package.xml string | SPDX | Pkgs | Confidence | Note |
|---|---|---:|---|---|
| `Apache License 2.0` | `Apache-2.0` | 788 | high | Spelling variant of the Apache License 2.0. |
| `BSD` | `BSD-3-Clause` | 634 | medium | Unversioned "BSD". In ROS this conventionally means the 3-clause license: 540 of the 567 packages with a license file nearby have BSD-3-Clause text (alone or next to another license), 9 have only BSD-2-Clause; 67 have no license file. |
| `Apache 2.0` | `Apache-2.0` | 223 | high | Spelling variant of the Apache License 2.0. |
| `Apache License, Version 2.0` | `Apache-2.0` | 40 | high | Spelling variant of the Apache License 2.0. |
| `Apache 2` | `Apache-2.0` | 38 | high | Spelling variant of the Apache License 2.0. |
| `GPLv3` | `GPL-3.0-only` | 38 | medium | GPL version 3 with no "or later" stated. Taken literally this is -only; source headers in some packages (control_box_rst, hector_rviz_overlay) say "or any later version", so those packages should probably declare GPL-3.0-or-later upstream. |
| `LGPLv3` | `LGPL-3.0-only` | 14 | medium | LGPL version 3 with no "or later" stated; taken literally as -only. |
| `Apache2` | `Apache-2.0` | 9 | high | Spelling variant of the Apache License 2.0. |
| `Apache-2` | `Apache-2.0` | 7 | high | Spelling variant of the Apache License 2.0. |
| `LGPL` | `LGPL-2.0-or-later` | 5 | low | No version given; literal mapping is LGPL-2.0-or-later (the earliest LGPL). The five packages actually ship LGPL-3 (ros_canopen, libphidget22), LGPL-2.1 (slam_toolbox, qpoases upstream) and nothing (lms1xx); they should be fixed upstream. |
| `zlib` | `Zlib` | 4 | high | Case/spelling variant of Zlib. |
| `Apache 2.0 License` | `Apache-2.0` | 3 | high | Spelling variant of the Apache License 2.0. |
| `BSD 3-Clause` | `BSD-3-Clause` | 3 | high | Spelling variant of BSD-3-Clause. |
| `BSD 3-clause` | `BSD-3-Clause` | 3 | high | Spelling variant of BSD-3-Clause. |
| `BSD-3` | `BSD-3-Clause` | 3 | high | Spelling variant of BSD-3-Clause. |
| `GPL` | `GPL-1.0-or-later` | 3 | low | No version given. The GPL lets the recipient pick any published version when none is specified, so the literal SPDX mapping is GPL-1.0-or-later. The three packages actually ship GPL-3 (imu_transformer), GPL-2 (wiimote) and nothing (imu_pipeline); they should be fixed upstream. |
| `GPL-3.0` | `GPL-3.0-only` | 3 | high | Deprecated SPDX id; SPDX defines it as identical to GPL-3.0-only. |
| `GPLv2` | `GPL-2.0-only` | 3 | medium | GPL version 2 with no "or later" stated; taken literally as -only. Headers in octovis and popf mostly say "or later". |
| `MIT License` | `MIT` | 3 | high | Spelling variant of MIT. |
| `Public Domain` | `LicenseRef-Public-Domain` | 3 | medium | SPDX has no identifier for public domain dedications; a LicenseRef- id is the SPDX-sanctioned way to name it. |
| `BSD-2` | `BSD-2-Clause` | 2 | high | Spelling variant of BSD-2-Clause. |
| `Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International Public License` | `CC-BY-NC-ND-4.0` | 2 | high | Full name of CC-BY-NC-ND-4.0. |
| `GNU Lesser Public License 2.1` | `LGPL-2.1-only` | 2 | medium | LGPL version 2.1 with no "or later" stated; taken literally as -only. |
| `LGPL v2.1` | `LGPL-2.1-only` | 2 | medium | LGPL version 2.1 with no "or later" stated; taken literally as -only. |
| `AGPLv3` | `AGPL-3.0-only` | 1 | medium | AGPL version 3 with no "or later" stated; taken literally as -only. |
| `Apache Licence 2.0` | `Apache-2.0` | 1 | high | Spelling variant of the Apache License 2.0. |
| `Apache License Version 2.0` | `Apache-2.0` | 1 | high | Spelling variant of the Apache License 2.0. |
| `Apache license 2.0` | `Apache-2.0` | 1 | high | Spelling variant of the Apache License 2.0. |
| `BSD 2-clause` | `BSD-2-Clause` | 1 | high | Spelling variant of BSD-2-Clause. |
| `BSD 3 Clause` | `BSD-3-Clause` | 1 | high | Spelling variant of BSD-3-Clause. |
| `BSD 3-Clause License` | `BSD-3-Clause` | 1 | high | Spelling variant of BSD-3-Clause. |
| `BSD Clause 3` | `BSD-3-Clause` | 1 | high | Spelling variant of BSD-3-Clause. |
| `BSD License 2.0` | `BSD-3-Clause` | 1 | medium | "BSD License 2.0" is an old name for the revised (3-clause) BSD license; the one package using it (teleop_twist_keyboard) ships BSD-3-Clause text. |
| `BSD, LGPL` | `BSD-3-Clause AND LGPL-3.0-only` | 1 | low | Two licenses in one tag. Only used by the phidgets_drivers metapackage, whose repo ships BSD-3-Clause and LGPL-3 license files. Written as an SPDX expression. |
| `CC0` | `CC0-1.0` | 1 | high | CC0 has only one version. |
| `Eclipse Distribution License 1.0` | `BSD-3-Clause` | 1 | high | SPDX has no EDL identifier; the Eclipse Distribution License 1.0 is the BSD-3-Clause text and SPDX directs it to BSD-3-Clause. |
| `Eclipse Public License 2.0` | `EPL-2.0` | 1 | high | Full name of EPL-2.0. |
| `GNU General Public License v2.0` | `GPL-2.0-only` | 1 | medium | GPL version 2 with no "or later" stated; taken literally as -only. |
| `GNU Lesser General Public License v3.0 (LGPL-3.0)` | `LGPL-3.0-only` | 1 | medium | LGPL version 3 with no "or later" stated; taken literally as -only. |
| `GPL-2` | `GPL-2.0-only` | 1 | medium | GPL version 2 with no "or later" stated; taken literally as -only. |
| `GPL-2.0` | `GPL-2.0-only` | 1 | high | Deprecated SPDX id; SPDX defines it as identical to GPL-2.0-only. |
| `GPLv2+ license` | `GPL-2.0-or-later` | 1 | high | "v2+" means version 2 or later. |
| `LGPL-3.0` | `LGPL-3.0-only` | 1 | high | Deprecated SPDX id; SPDX defines it as identical to LGPL-3.0-only. |
| `LGPL-v3` | `LGPL-3.0-only` | 1 | medium | LGPL version 3 with no "or later" stated; taken literally as -only. |
| `LGPLv2.1` | `LGPL-2.1-only` | 1 | medium | LGPL version 2.1 with no "or later" stated; taken literally as -only. |
| `MPL-2.0 license` | `MPL-2.0` | 1 | high | Spelling variant of MPL-2.0. |
| `Mozilla Public License 2.0` | `MPL-2.0` | 1 | high | Spelling variant of MPL-2.0. |
| `Universal Robots A/S’ Terms and Conditions for Use of Graphical Documentation` | `LicenseRef-UR-Graphical-Documentation` | 1 | medium | Proprietary Universal Robots terms with no SPDX id; a LicenseRef- id names it. |
| `Zlib License` | `Zlib` | 1 | high | Case/spelling variant of Zlib. |
| `apache 2.0` | `Apache-2.0` | 1 | high | Spelling variant of the Apache License 2.0. |
| `zlib License` | `Zlib` | 1 | high | Case/spelling variant of Zlib. |

### Not mapped

| package.xml string | Pkgs | Package | Note |
|---|---:|---|---|
| `MyLicense` | 1 | `smacc2/smacc2_performance_tools/performance_tests/sm_coretest_transition_speed_1/package.xml` | Template placeholder (smacc2 performance test package). Nothing to map; should be fixed upstream. |
| `TODO: License declaration` | 1 | `wato_monorepo/src/action/wato_trajectory_msgs/package.xml` | ros2 pkg create placeholder (wato_trajectory_msgs). Nothing to map; should be fixed upstream. |

## Evidence for `BSD`

License text found near the 634 packages declaring `BSD`:

| License file text | Packages |
|---|---:|
| BSD-3-Clause | 503 |
| (no license file found) | 67 |
| BSD-3-Clause+GPL-3+LGPL-3 | 21 |
| Apache-2.0 | 14 |
| Apache-2.0+BSD-3-Clause | 13 |
| BSD-2-Clause | 9 |
| BSD-4-Clause+MIT | 2 |
| BSD-3-Clause+MIT | 2 |
| LGPL-3 | 2 |
| Apache-2.0+BSD-3-Clause+MIT | 1 |

Where only Apache-2.0 or another license was found, the nearest file is often at repo level and may not describe that package.

## GPL-family packages that may be under-declared

These declare a version without "or later", but their source headers mostly say "or any later version". The alias still maps them to `-only` (what they declare); upstream may want to change the tag.

| Package | Declared | Headers "or later" / version only |
|---|---|---|
| `control_box_rst/package.xml` | `GPLv3` | 148 / 0 |
| `eiquadprog/package.xml` | `LGPLv3` | 7 / 2 |
| `hector_rviz_overlay/hector_rviz_overlay/package.xml` | `GPLv3` | 75 / 0 |
| `hector_rviz_overlay/hector_rviz_overlay_controls/package.xml` | `GPLv3` | 8 / 0 |
| `hector_rviz_overlay/hector_rviz_overlay_demo/package.xml` | `GPLv3` | 8 / 0 |
| `octomap/octovis/package.xml` | `GPLv2` | 54 / 25 |
| `popf/package.xml` | `GPLv2` | 152 / 0 |
| `ros2_canopen/canopen_402_driver/package.xml` | `LGPL-v3` | 24 / 0 |
| `rqt_multiplot/package.xml` | `GNU Lesser General Public License v3.0 (LGPL-3.0)` | 195 / 0 |

## Low-confidence strings: affected packages

**`GPL`** → `GPL-1.0-or-later`

- `imu_pipeline/imu_pipeline/package.xml` (no license file found)
- `imu_pipeline/imu_transformer/package.xml` (imu_pipeline/imu_transformer/LICENSE: GPL-3)
- `joystick_drivers/wiimote/package.xml` (joystick_drivers/wiimote/LICENSE: GPL-2)

**`LGPL`** → `LGPL-2.0-or-later`

- `lms1xx/package.xml` (no license file found)
- `phidgets_drivers/libphidget22/package.xml` (phidgets_drivers/LICENSE.bsd: BSD-3-Clause; phidgets_drivers/LICENSE.gplv3: GPL-3; phidgets_drivers/LICENSE.lgplv3: LGPL-3; phidgets_drivers/LICENSE: unrecognized)
- `qpoases_vendor/package.xml` (qpoases_vendor/LICENSE: Apache-2.0)
- `ros_canopen/ros_canopen/package.xml` (ros_canopen/LICENSE: LGPL-3)
- `slam_toolbox/package.xml` (slam_toolbox/LICENSE: LGPL-2.1)

**`BSD, LGPL`** → `BSD-3-Clause AND LGPL-3.0-only`

- `phidgets_drivers/phidgets_drivers/package.xml` (phidgets_drivers/LICENSE.bsd: BSD-3-Clause; phidgets_drivers/LICENSE.gplv3: GPL-3; phidgets_drivers/LICENSE.lgplv3: LGPL-3; phidgets_drivers/LICENSE: unrecognized)

## Strings that are already SPDX

| String | Pkgs | Status |
|---|---:|---|
| `Apache-2.0` | 495 | current |
| `MIT` | 280 | current |
| `BSD-3-Clause` | 202 | current |
| `GPL-3.0-or-later` | 152 | current |
| `BSD-2-Clause` | 15 | current |
| `GPL-3.0-only` | 8 | current |
| `MIT-0` | 6 | current |
| `GPL-2.0-or-later` | 3 | current |
| `GPL-3.0` | 3 | deprecated, aliased |
| `Zlib` | 3 | current |
| `LGPL-2.1-or-later` | 3 | current |
| `BSL-1.0` | 2 | current |
| `MPL-2.0` | 2 | current |
| `MPL-1.1` | 1 | current |
| `CC0-1.0` | 1 | current |
| `GPL-2.0` | 1 | deprecated, aliased |
| `AGPL-3.0-only` | 1 | current |
| `LGPL-3.0` | 1 | deprecated, aliased |
| `BSD-1-Clause` | 1 | current |
| `LGPL-3.0-or-later` | 1 | current |
| `CC-BY-3.0` | 1 | current |
| `CC-BY-NC-SA-3.0` | 1 | current |
| `CC-BY-NC-SA-4.0` | 1 | current |
| `WTFPL` | 1 | current |
| `HPND` | 1 | current |
| `Unlicense` | 1 | current |
| `EPL-2.0` | 1 | current |

## Other observations

- `_plugins/rosindex_generator.rb` reads only the first `<license>` tag (`REXML::XPath.first`), so 85 packages currently show only part of their licensing.
- Several packages declare a valid SPDX id that disagrees with the license file in the repo (e.g. `MIT` declared next to an Apache-2.0 repo LICENSE). Aliasing can't detect or fix these, so they are left as is.
- Some packages list the same license twice (e.g. `gtsam`, `mola_test_datasets`); dedupe when building an expression.
