#!/usr/bin/env ruby
# frozen_string_literal: true

# Añade al proyecto de Xcode:
#   - la extensión de widgets "IntiWidget" (SwiftUI + WidgetKit),
#   - los atajos de Siri/Atajos (IntiShortcuts.swift) dentro de Runner,
#   - el App Group `group.co.inti.app` (entitlements) en ambos.
#
# Se ejecuta en el Mac de Codemagic antes de compilar (ver codemagic.yaml).
# Es idempotente: si la extensión ya existe, no hace nada.
#
# Uso:  ruby ios/scripts/add_widget_extension.rb
#
# Requiere la gema `xcodeproj` (viene con CocoaPods).

require 'xcodeproj'

ROOT = File.expand_path('..', __dir__) # carpeta ios/
PROJECT_PATH = File.join(ROOT, 'Runner.xcodeproj')
EXT_NAME = 'IntiWidget'
APP_BUNDLE_ID = 'co.inti.app'
EXT_BUNDLE_ID = "#{APP_BUNDLE_ID}.#{EXT_NAME}"
EXT_DEPLOYMENT = '16.0'

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'No encontré el target Runner' if runner.nil?

if project.targets.any? { |t| t.name == EXT_NAME }
  puts "#{EXT_NAME} ya existe: no hay nada que hacer."
  exit 0
end

# --- 1. Archivos de la app (atajos + entitlements) ---------------------------

runner_group = project.main_group.find_subpath('Runner', false)
abort 'No encontré el grupo Runner' if runner_group.nil?

shortcuts_ref = runner_group.new_file('IntiShortcuts.swift')
runner.add_file_references([shortcuts_ref])

runner_entitlements = runner_group.new_file('Runner.entitlements')

runner.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

# --- 2. La extensión ----------------------------------------------------------

ext = project.new_target(:app_extension, EXT_NAME, :ios, EXT_DEPLOYMENT)

ext_group = project.main_group.new_group(EXT_NAME, EXT_NAME)
swift_ref = ext_group.new_file('IntiWidget.swift')
ext_group.new_file('Info.plist')
ext_group.new_file('IntiWidget.entitlements')
ext.add_file_references([swift_ref])

runner_configs = runner.build_configurations.to_h { |c| [c.name, c] }

ext.build_configurations.each do |config|
  settings = config.build_settings
  # Hereda el xcconfig de Flutter para tener FLUTTER_BUILD_NAME/NUMBER.
  runner_config = runner_configs[config.name]
  config.base_configuration_reference = runner_config.base_configuration_reference if runner_config

  settings['PRODUCT_BUNDLE_IDENTIFIER'] = EXT_BUNDLE_ID
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['INFOPLIST_FILE'] = "#{EXT_NAME}/Info.plist"
  settings['CODE_SIGN_ENTITLEMENTS'] = "#{EXT_NAME}/#{EXT_NAME}.entitlements"
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['SWIFT_VERSION'] = '5.0'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = EXT_DEPLOYMENT
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['SKIP_INSTALL'] = 'YES'
  settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'
  ]
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS'] = 'NO'
end

# --- 3. Incrustar la extensión en la app --------------------------------------

runner.add_dependency(ext)

embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.dst_subfolder_spec = '13' # PlugIns
build_file = embed.add_file_reference(ext.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Debe ir ANTES de "Thin Binary": si va después, Xcode detecta un ciclo de
# dependencias entre las fases.
phases = runner.build_phases
thin_index = phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
embed_index = phases.index(embed)
if thin_index && embed_index && embed_index > thin_index
  if phases.respond_to?(:move)
    phases.move(embed, thin_index)
  else
    phases.delete_at(embed_index)
    phases.insert(thin_index, embed)
  end
end

order = runner.build_phases.map { |p| p.respond_to?(:name) && p.name ? p.name : p.isa }
puts "Fases de Runner: #{order.join(' > ')}"
embed_pos = order.index('Embed Foundation Extensions')
thin_pos = order.index('Thin Binary')
if embed_pos && thin_pos && embed_pos > thin_pos
  abort 'La fase de incrustar quedó después de "Thin Binary": se detiene para no generar un ciclo.'
end

project.save
puts "Listo: #{EXT_NAME} añadido (#{EXT_BUNDLE_ID}) y atajos incluidos en Runner."
