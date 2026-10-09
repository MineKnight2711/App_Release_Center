/// What QA Desk drives when it operates an app itself: the app, its
/// environments, the demo accounts that log into it, and the scenarios
/// written as steps.
library;

enum QaAppPlatform {
  android('android'),
  web('web');

  const QaAppPlatform(this.value);

  final String value;

  static QaAppPlatform parse(String? value) => QaAppPlatform.values.firstWhere(
    (item) => item.value == value,
    orElse: () => QaAppPlatform.android,
  );
}

/// One backend an app can run against, and the build that talks to it.
class QaAppEnvironment {
  const QaAppEnvironment({
    required this.name,
    this.appId = '',
    this.url = '',
    this.build = '',
    this.production = false,
  });

  /// `staging`, `production`, or any name the project uses.
  final String name;

  /// Android package of this environment's build.
  final String appId;

  /// Web address, for `platform: web`.
  final String url;

  /// APK or AAB to install, relative to the project folder.
  final String build;

  /// Marked explicitly in the manifest; `production` and `prod` count anyway.
  final bool production;

  bool get isProduction {
    final lower = name.toLowerCase();
    return production || lower == 'production' || lower == 'prod';
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (appId.isNotEmpty) 'appId': appId,
    if (url.isNotEmpty) 'url': url,
    if (build.isNotEmpty) 'build': build,
    if (production) 'production': true,
  };

  factory QaAppEnvironment.fromJson(Map<String, dynamic> json) =>
      QaAppEnvironment(
        name: json['name']?.toString() ?? '',
        appId: json['appId']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        build: json['build']?.toString() ?? '',
        production: json['production'] == true,
      );
}

/// An app a project declares under `apps:` in `.fiza-qa/project.yaml`.
class QaApp {
  const QaApp({
    required this.id,
    required this.name,
    this.platform = QaAppPlatform.android,
    this.environments = const [],
    this.loginFlow = '',
    this.cleanupFlow = '',
    this.productionGuard = const [],
  });

  final String id;
  final String name;
  final QaAppPlatform platform;
  final List<QaAppEnvironment> environments;

  /// Flow that logs in with `${MAESTRO_QA_USERNAME}` and
  /// `${MAESTRO_QA_PASSWORD}`, relative to `.fiza-qa/`.
  final String loginFlow;

  /// Flow run after a writing scenario on a non-production environment.
  final String cleanupFlow;

  /// Labels a scenario may never tap when it runs against production.
  final List<String> productionGuard;

  QaAppEnvironment? environment(String name) {
    for (final item in environments) {
      if (item.name == name) return item;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'platform': platform.value,
    'environments': environments.map((item) => item.toJson()).toList(),
    if (loginFlow.isNotEmpty) 'login': loginFlow,
    if (cleanupFlow.isNotEmpty) 'cleanup': cleanupFlow,
    if (productionGuard.isNotEmpty) 'productionGuard': productionGuard,
  };

  factory QaApp.fromJson(Map<String, dynamic> json) => QaApp(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    platform: QaAppPlatform.parse(json['platform']?.toString()),
    environments: [
      for (final item in json['environments'] as List<dynamic>? ?? const [])
        QaAppEnvironment.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    loginFlow: json['login']?.toString() ?? '',
    cleanupFlow: json['cleanup']?.toString() ?? '',
    productionGuard: [
      for (final item in json['productionGuard'] as List<dynamic>? ?? const [])
        item.toString(),
    ],
  );
}

enum AccountAccess {
  readWrite('readWrite'),
  readOnly('readOnly');

  const AccountAccess(this.value);

  final String value;

  static AccountAccess parse(String? value) => value == readOnly.value
      ? AccountAccess.readOnly
      : AccountAccess.readWrite;
}

enum AccountStatus {
  ok('ok'),
  loginFailed('loginFailed'),
  disabled('disabled');

  const AccountStatus(this.value);

  final String value;

  static AccountStatus parse(String? value) => AccountStatus.values.firstWhere(
    (item) => item.value == value,
    orElse: () => AccountStatus.ok,
  );
}

/// A demo account the team hands QA Desk to log into an app with.
class DemoAccount {
  const DemoAccount({
    required this.id,
    required this.app,
    required this.environment,
    required this.role,
    required this.username,
    required this.password,
    this.extra = const {},
    this.access = AccountAccess.readWrite,
    this.notes = '',
    this.status = AccountStatus.ok,
    this.statusMessage = '',
    this.statusAt,
    this.updatedAt,
    this.updatedBy = '',
  });

  final String id;

  /// Id of the [QaApp] it logs into.
  final String app;
  final String environment;

  /// The team's own label: "Chủ shop", "Nhân viên"… Scenarios ask for a role,
  /// never for a person.
  final String role;
  final String username;
  final String password;

  /// More values a login may need, such as a shop code or a PIN; each becomes
  /// `${MAESTRO_QA_<KEY>}`.
  final Map<String, String> extra;
  final AccountAccess access;
  final String notes;
  final AccountStatus status;
  final String statusMessage;
  final DateTime? statusAt;
  final DateTime? updatedAt;
  final String updatedBy;

  /// Production accounts are read-only whatever they were saved as.
  AccountAccess effectiveAccess(bool production) =>
      production ? AccountAccess.readOnly : access;

  /// Values that must never appear in a log, report or artifact.
  List<String> get secretValues => [password, ...extra.values];

  /// The variables a flow reads, as Maestro picks them up from the process
  /// environment.
  Map<String, String> get flowEnvironment => {
    'MAESTRO_QA_USERNAME': username,
    'MAESTRO_QA_PASSWORD': password,
    for (final entry in extra.entries)
      'MAESTRO_QA_${_variableName(entry.key)}': entry.value,
  };

  /// `0912•••789`: enough to tell accounts apart, not enough to log in.
  String get maskedUsername {
    if (username.length <= 4) return '•' * username.length;
    final head = username.length > 7 ? 4 : 2;
    final tail = username.length > 7 ? 3 : 2;
    return '${username.substring(0, head)}'
        '${'•' * (username.length - head - tail)}'
        '${username.substring(username.length - tail)}';
  }

  DemoAccount copyWith({
    String? app,
    String? environment,
    String? role,
    String? username,
    String? password,
    Map<String, String>? extra,
    AccountAccess? access,
    String? notes,
    AccountStatus? status,
    String? statusMessage,
    DateTime? statusAt,
    DateTime? updatedAt,
    String? updatedBy,
  }) => DemoAccount(
    id: id,
    app: app ?? this.app,
    environment: environment ?? this.environment,
    role: role ?? this.role,
    username: username ?? this.username,
    password: password ?? this.password,
    extra: extra ?? this.extra,
    access: access ?? this.access,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    statusMessage: statusMessage ?? this.statusMessage,
    statusAt: statusAt ?? this.statusAt,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
  );

  /// Plain form, for the local vault inside Windows secure storage. The team
  /// vault encrypts the secret fields before they leave the machine.
  Map<String, dynamic> toJson() => {
    'id': id,
    'app': app,
    'environment': environment,
    'role': role,
    'username': username,
    'password': password,
    'extra': extra,
    'access': access.value,
    'notes': notes,
    'status': status.value,
    'statusMessage': statusMessage,
    'statusAt': statusAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'updatedBy': updatedBy,
  };

  factory DemoAccount.fromJson(Map<String, dynamic> json) => DemoAccount(
    id: json['id']?.toString() ?? '',
    app: json['app']?.toString() ?? '',
    environment: json['environment']?.toString() ?? '',
    role: json['role']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    password: json['password']?.toString() ?? '',
    extra: {
      for (final entry
          in (json['extra'] as Map<dynamic, dynamic>? ?? const {}).entries)
        entry.key.toString(): entry.value.toString(),
    },
    access: AccountAccess.parse(json['access']?.toString()),
    notes: json['notes']?.toString() ?? '',
    status: AccountStatus.parse(json['status']?.toString()),
    statusMessage: json['statusMessage']?.toString() ?? '',
    statusAt: DateTime.tryParse(json['statusAt']?.toString() ?? ''),
    updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    updatedBy: json['updatedBy']?.toString() ?? '',
  );
}

String _variableName(String key) =>
    key.toUpperCase().replaceAll(RegExp('[^A-Z0-9]+'), '_');

enum AutomationStepType {
  launch('launch', 'Mở app'),
  login('login', 'Đăng nhập bằng tài khoản demo'),
  tap('tap', 'Bấm vào'),
  input('input', 'Nhập'),
  assertVisible('assertVisible', 'Thấy'),
  assertNotVisible('assertNotVisible', 'Không thấy'),
  waitFor('waitFor', 'Chờ tới khi thấy'),
  scrollTo('scrollTo', 'Cuộn tới'),
  back('back', 'Quay lại'),
  screenshot('screenshot', 'Chụp màn hình'),
  runFlow('runFlow', 'Chạy flow con');

  const AutomationStepType(this.value, this.label);

  final String value;
  final String label;

  /// Whether the step points at something on screen.
  bool get hasTarget => switch (this) {
    tap || assertVisible || assertNotVisible || waitFor || scrollTo => true,
    input || runFlow || screenshot => true,
    launch || login || back => false,
  };

  static AutomationStepType parse(String? value) =>
      AutomationStepType.values.firstWhere(
        (item) => item.value == value,
        orElse: () => AutomationStepType.tap,
      );
}

/// One step of a scenario QA Desk operates itself.
class AutomationStep {
  const AutomationStep({
    required this.type,
    this.target = '',
    this.value = '',
    this.byId = false,
    this.clearState = false,
    this.partial = false,
  });

  final AutomationStepType type;

  /// Text on screen, an accessibility id when [byId], a screenshot name, or
  /// a flow path, depending on [type].
  final String target;

  /// What [AutomationStepType.input] types; may use `${MAESTRO_QA_…}`.
  final String value;
  final bool byId;

  /// For [AutomationStepType.launch]: start from a fresh install state.
  final bool clearState;

  /// Matches text anywhere in an element, not only a whole line of it.
  final bool partial;

  /// The step read as a sentence, for lists and reports.
  String get summary {
    final sentence = _sentence;
    return partial && target.isNotEmpty && !byId
        ? '$sentence (khớp một phần)'
        : sentence;
  }

  String get _sentence => switch (type) {
    AutomationStepType.launch =>
      clearState ? 'Mở app, xoá dữ liệu cũ' : 'Mở app',
    AutomationStepType.login => 'Đăng nhập bằng tài khoản demo',
    AutomationStepType.input =>
      target.isEmpty
          ? 'Nhập "$value"'
          : 'Nhập "$value" vào ${byId ? 'id ' : ''}"$target"',
    AutomationStepType.back => 'Quay lại',
    AutomationStepType.screenshot => 'Chụp màn hình "$target"',
    AutomationStepType.runFlow => 'Chạy flow con $target',
    _ => '${type.label} ${byId ? 'id ' : ''}"$target"',
  };

  Map<String, dynamic> toJson() => {
    'type': type.value,
    if (target.isNotEmpty) 'target': target,
    if (value.isNotEmpty) 'value': value,
    if (byId) 'byId': true,
    if (clearState) 'clearState': true,
    if (partial) 'partial': true,
  };

  factory AutomationStep.fromJson(Map<String, dynamic> json) => AutomationStep(
    type: AutomationStepType.parse(json['type']?.toString()),
    target: json['target']?.toString() ?? '',
    value: json['value']?.toString() ?? '',
    byId: json['byId'] == true,
    clearState: json['clearState'] == true,
    partial: json['partial'] == true,
  );
}

/// What turns a test case into one QA Desk operates itself.
class AutomationSpec {
  const AutomationSpec({
    required this.app,
    required this.role,
    this.writes = false,
    this.environments = const [],
    this.steps = const [],
    this.flow = '',
  });

  /// Id of the [QaApp] under test.
  final String app;

  /// Role of the demo account to log in with.
  final String role;

  /// Creates, changes or deletes data: never runs against production.
  final bool writes;

  /// Environments this scenario may run in; empty means any it is allowed.
  final List<String> environments;
  final List<AutomationStep> steps;

  /// Flow file relative to `.fiza-qa/`; written from [steps] on save.
  final String flow;

  bool allowsEnvironment(QaAppEnvironment environment) {
    if (writes && environment.isProduction) return false;
    return environments.isEmpty || environments.contains(environment.name);
  }

  AutomationSpec copyWith({String? flow}) => AutomationSpec(
    app: app,
    role: role,
    writes: writes,
    environments: environments,
    steps: steps,
    flow: flow ?? this.flow,
  );

  Map<String, dynamic> toJson() => {
    'app': app,
    'role': role,
    'writes': writes,
    'environments': environments,
    'steps': steps.map((step) => step.toJson()).toList(),
    if (flow.isNotEmpty) 'flow': flow,
  };

  factory AutomationSpec.fromJson(Map<String, dynamic> json) => AutomationSpec(
    app: json['app']?.toString() ?? '',
    role: json['role']?.toString() ?? '',
    writes: json['writes'] == true,
    environments: [
      for (final item in json['environments'] as List<dynamic>? ?? const [])
        item.toString(),
    ],
    steps: [
      for (final item in json['steps'] as List<dynamic>? ?? const [])
        AutomationStep.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    flow: json['flow']?.toString() ?? '',
  );
}
