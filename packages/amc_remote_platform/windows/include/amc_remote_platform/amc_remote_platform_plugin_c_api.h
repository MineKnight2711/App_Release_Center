#ifndef AMC_REMOTE_PLATFORM_PLUGIN_C_API_H_
#define AMC_REMOTE_PLATFORM_PLUGIN_C_API_H_
#include <flutter_plugin_registrar.h>
#ifdef FLUTTER_PLUGIN_IMPL
#define AMC_REMOTE_EXPORT __declspec(dllexport)
#else
#define AMC_REMOTE_EXPORT __declspec(dllimport)
#endif
extern "C" AMC_REMOTE_EXPORT void AmcRemotePlatformPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);
#endif
