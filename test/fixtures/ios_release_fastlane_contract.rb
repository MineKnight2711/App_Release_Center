# Loaded only by the local Fastlane contract smoke test. No Apple/network calls.
require 'ostruct'
require 'fastlane/actions/app_store_connect_api_key'
require 'fastlane/actions/upload_to_testflight'
require 'fastlane/actions/upload_to_app_store'

$amc_calls = []
class AmcFakeLocalization
  def initialize(locale); @locale = locale; end
  def locale; @locale; end
  def update(attributes:)
    raise 'Shared metadata must not be changed' unless attributes.keys == [:whats_new]
    $amc_calls << { action: 'notes', locale: locale, attributes: attributes }
  end
end
class AmcFakeVersion
  def initialize(version = '1.2.3', created = '2026-10-12T00:00:00Z')
    @version = version
    @created = created
  end
  def version_string; @version; end
  def created_date; @created; end
  def app_version_state; 'PREPARE_FOR_SUBMISSION'; end
  def app_store_state; 'PREPARE_FOR_SUBMISSION'; end
  def id; "version-#{version_string}"; end
  def get_build; OpenStruct.new(version: '12'); end
  def get_app_store_version_localizations
    [AmcFakeLocalization.new('vi'), AmcFakeLocalization.new('fr-FR')]
  end
  def select_build(build_id:); $amc_calls << { action: 'select_build', build_id: build_id }; end
  def create_app_store_version_release_request; $amc_calls << { action: 'release' }; end
end
class AmcFakeApp
  def id; 'app'; end
  def primary_locale; ENV['AMC_TEST_VERSIONS'] == 'automatic' ? 'fr-FR' : 'vi'; end
  def ensure_version!(version, platform:)
    raise 'Unexpected draft version/platform' unless version == '1.2.3' && platform == 'IOS'
    $amc_calls << { action: 'ensure_version', version: version }
  end
  # Unlike the Spaceship Ruby signature, Apple's endpoint rejects sort.
  def get_app_store_versions(filter: {}, includes: nil, limit: nil, **unsupported)
    raise "Apple appStoreVersions endpoint rejects #{unsupported.keys.join(', ')}" unless unsupported.empty?
    versions = if ENV['AMC_TEST_VERSIONS'] == 'first-release'
      [AmcFakeVersion.new]
    elsif ENV['AMC_TEST_VERSIONS'] == 'many'
      (1..22).map { |index| AmcFakeVersion.new("2.#{index}.0", "2026-10-#{index.to_s.rjust(2, '0')}T00:00:00Z") } +
        [AmcFakeVersion.new('1.2.3', '2025-01-01T00:00:00Z')]
    else
      [AmcFakeVersion.new('0.9.0', '2025-01-01T00:00:00Z'),
     AmcFakeVersion.new,
     AmcFakeVersion.new('2.0.0', '2026-10-13T00:00:00Z')]
    end
    limit ? versions.first(limit) : versions
  end
  def get_edit_app_store_version(**_); AmcFakeVersion.new; end
  def get_pending_release_app_store_version(**_); AmcFakeVersion.new; end
end
class << Spaceship::ConnectAPI::App
  def find(_); AmcFakeApp.new; end
end
class << Spaceship::ConnectAPI::Build
  def all(**_)
    return [] if ENV['AMC_TEST_ACTION'] == 'upload'
    [OpenStruct.new(id: 'build-12', version: '12', app_version: '1.2.3', processing_state: 'VALID', expired: false)]
  end
end
class << Fastlane::Actions::AppStoreConnectApiKeyAction
  def run(_); { key_id: 'test', issuer_id: 'test', key: 'test' }; end
end
class << Fastlane::Actions::UploadToTestflightAction
  def run(options)
    $amc_calls << { action: 'testflight', distribute_only: options[:distribute_only], version: options[:app_version], build: options[:build_number], external: options[:distribute_external] }
  end
end
class << Fastlane::Actions::UploadToAppStoreAction
  def run(options)
    $amc_calls << { action: 'appstore', binary: options[:skip_binary_upload], review: options[:submit_for_review], automatic: options[:automatic_release], build: options[:build_number], skip_metadata: options[:skip_metadata], release_notes: options[:release_notes] }
  end
end
at_exit { puts "AMC_CONTRACT:#{JSON.generate($amc_calls)}" }
