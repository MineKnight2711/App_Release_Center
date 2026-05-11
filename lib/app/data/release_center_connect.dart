import 'package:get/get.dart';

class ReleaseCenterConnect extends GetConnect {
  @override
  void onInit() {
    httpClient.timeout = const Duration(seconds: 20);
    super.onInit();
  }
}
