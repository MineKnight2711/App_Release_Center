/// Shared by AMC and exported terminal scripts. Inputs are a JSON file, never
/// interpolated Ruby or shell source; private keys stay outside the artifact.
const iosReleaseFastfile = r'''
require 'json'
default_platform(:ios)

platform :ios do
  lane :amc_ios do |options|
    input = JSON.parse(File.read(options[:input].to_s))
    action = input.fetch('action')
    api_key = app_store_connect_api_key(
      key_id: input.fetch('key_id'), issuer_id: input.fetch('issuer_id'),
      key_filepath: input.fetch('key_filepath'), in_house: false,
      duration: 1200
    )
    app = Spaceship::ConnectAPI::App.find(input.fetch('bundle_id'))
    UI.user_error!('Bundle ID not accessible with this API key') unless app
    version = input.fetch('version')
    number = input['build_number'].to_s
    builds = Spaceship::ConnectAPI::Build.all(
      app_id: app.id, version: version, platform: 'IOS', limit: 200
    )
    build = builds.find { |b| b.version.to_s == number }
    ready = build && build.processing_state == 'VALID' && !build.expired
    if input.fetch('declare_no_encryption', false) && ready &&
       build.uses_non_exempt_encryption.nil? && %w[compliance draft submit].include?(action)
      # "None of the algorithms mentioned above" in App Store Connect. Only
      # fills a missing answer; Info.plist or an earlier answer is kept.
      # distribute leaves it to upload_to_testflight, which waits for Apple.
      build.update(attributes: { usesNonExemptEncryption: false })
    end
    case action
    when 'query'
      # Read only, also includes failed/processing builds for collision checks.
    when 'compliance'
      UI.user_error!('Selected build is not ready') unless ready
      UI.user_error!('Export compliance declaration is off for this project') unless input.fetch('declare_no_encryption', false)
    when 'upload'
      UI.user_error!('Build number already exists on Apple; refresh status') if build
      upload_to_testflight(
        api_key: api_key, app_identifier: input.fetch('bundle_id'),
        ipa: input.fetch('ipa'), skip_waiting_for_build_processing: true,
        distribute_external: false, skip_submission: true
      )
    when 'distribute'
      UI.user_error!('Selected build is not ready') unless ready
      groups = input.fetch('groups', [])
      UI.user_error!('Select at least one TestFlight group') if groups.empty?
      upload_to_testflight(
        api_key: api_key, app_identifier: input.fetch('bundle_id'),
        distribute_only: true, app_version: version, build_number: number,
        groups: groups, changelog: input.fetch('notes', ''),
        distribute_external: input.fetch('external_testing', false),
        submit_beta_review: input.fetch('external_testing', false)
      )
    when 'draft', 'submit'
      UI.user_error!('Selected build is not ready') unless ready
      # Ensure the draft without activating locales or touching shared App Info.
      app.ensure_version!(version, platform: 'IOS')
      edit = app.get_edit_app_store_version(platform: 'IOS')
      UI.user_error!('Draft version mismatch') unless edit && edit.version_string == version
      notes = input.fetch('notes', '').strip
      if !notes.empty? && app.get_app_store_versions(filter: { platform: 'IOS' }, includes: nil, limit: 2).length > 1
        requested_locale = input.fetch('locale', 'vi-VN').to_s.strip
        if !input.key?('use_app_store_locale') && ['', 'en-US'].include?(requested_locale)
          requested_locale = 'vi-VN'
        end
        locale = input.fetch('use_app_store_locale', false) ? app.primary_locale.to_s : requested_locale
        locale = 'vi' if locale.downcase == 'vi-vn'
        UI.user_error!('App Store primary language is unavailable') if locale.empty?
        localization = edit.get_app_store_version_localizations.find { |item| item.locale == locale }
        UI.user_error!("Locale #{locale} is not configured for this App Store version. Select an existing locale in AMC or configure it in App Store Connect.") unless localization
        # Update only What's New on an existing version localization. deliver's
        # metadata upload can activate new languages and copy shared App Info.
        localization.update(attributes: { whats_new: notes })
      end
      edit.select_build(build_id: build.id)
      upload_to_app_store(
        api_key: api_key, app_identifier: input.fetch('bundle_id'),
        app_version: version, build_number: number, skip_binary_upload: true,
        skip_screenshots: true, skip_metadata: true,
        submit_for_review: action == 'submit',
        automatic_release: input.fetch('automatic_release', false),
        run_precheck_before_submit: action == 'submit',
        precheck_include_in_app_purchases: false, force: true
      )
    when 'release'
      pending = app.get_pending_release_app_store_version(platform: 'IOS')
      UI.user_error!('Version is not pending developer release') unless pending && pending.version_string == version
      selected = pending.get_build
      UI.user_error!('Pending version uses a different build') unless selected && selected.version.to_s == number
      pending.create_app_store_version_release_request
    else
      UI.user_error!("Unsupported AMC action #{action}")
    end
    builds = Spaceship::ConnectAPI::Build.all(app_id: app.id, version: version, platform: 'IOS', limit: 200)
    # Apple does not accept sort on /apps/{id}/appStoreVersions. Fetch all
    # pages before ordering locally, then retain the selected version even
    # when it is older than the twenty most recently created versions.
    versions = app.get_app_store_versions(filter: { platform: 'IOS' }, includes: 'build')
    versions = versions.sort_by { |v| v.created_date.to_s }.reverse
    versions = (versions.first(20) + versions.select { |v| v.version_string == version }).uniq(&:id)
    result = {
      primaryLocale: app.primary_locale,
      builds: builds.map { |b| { id: b.id, version: b.app_version, number: b.version, state: b.processing_state, expired: b.expired, missingCompliance: b.uses_non_exempt_encryption.nil? } },
      versions: versions.map { |v| { version: v.version_string, state: v.app_version_state || v.app_store_state, id: v.id, buildNumber: v.version_string == version ? v.get_build&.version : nil } }
    }
    puts "AMC_IOS_RESULT:#{JSON.generate(result)}"
  end
end
''';
