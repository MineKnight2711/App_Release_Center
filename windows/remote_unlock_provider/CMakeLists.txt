add_library(amc_remote_unlock_provider SHARED
  "remote_unlock_provider.cpp"
  "remote_unlock_provider.def"
)

target_compile_features(amc_remote_unlock_provider PRIVATE cxx_std_17)
target_compile_options(amc_remote_unlock_provider PRIVATE /W4 /WX /EHsc /utf-8)
target_compile_definitions(amc_remote_unlock_provider PRIVATE
  UNICODE
  _UNICODE
  SECURITY_WIN32
  NOMINMAX
)
target_link_libraries(amc_remote_unlock_provider PRIVATE
  advapi32.lib
  crypt32.lib
  credui.lib
  ncrypt.lib
  ole32.lib
  secur32.lib
  shlwapi.lib
)

set_target_properties(amc_remote_unlock_provider PROPERTIES
  OUTPUT_NAME "amc_remote_unlock_provider"
  PREFIX ""
)
