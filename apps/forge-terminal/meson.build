project('forge-terminal', 'c',
  version: '1.0.0',
  license: 'GPL-3.0-or-later',
  default_options: ['c_std=c11', 'warning_level=2'])

# gtk4-layer-shell first: it has to be linked before libwayland-client.
layer = dependency('gtk4-layer-shell-0')
gtk = dependency('gtk4')
vte = dependency('vte-2.91-gtk4')
json = dependency('json-glib-1.0')

add_project_arguments('-DFORGE_VERSION="@0@"'.format(meson.project_version()), language: 'c')

theme = static_library('forge-theme', 'src/theme.c', dependencies: [gtk, json])

executable('forge-terminal', 'src/main.c',
  link_with: theme,
  dependencies: [layer, gtk, vte, json],
  install: true)

install_data('data/org.forgeos.terminal.desktop', install_dir: get_option('datadir') / 'applications')

test_theme = executable('test-theme', 'tests/test-theme.c', link_with: theme, dependencies: [gtk, json])
test('theme and settings', test_theme)
