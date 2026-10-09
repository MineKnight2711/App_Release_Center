/// One thing standing between a magic packet and a machine that wakes up.
class WakeBlocker {
  const WakeBlocker({
    required this.title,
    required this.detail,
    required this.fix,
    required this.fatal,
  });

  final String title;
  final String detail;

  /// What the person has to go and do. Empty when there is nothing to do.
  final String fix;

  /// True when no amount of retrying will help.
  final bool fatal;
}

/// What the desktop knows about its own ability to be woken and to come back.
///
/// Read on the machine and published in the heartbeat, because by the time the
/// phone needs any of it the machine is asleep and cannot be asked. A field
/// being null means "could not read", which is deliberately different from
/// false — telling someone Wake-on-LAN is off when it simply could not be
/// checked sends them into a BIOS for nothing.
class WakeDiagnostics {
  const WakeDiagnostics({
    this.adapterName = '',
    this.wirelessAdapter = false,
    this.macAddress = '',
    this.ipAddress = '',
    this.probeListening = false,
    this.lastPacketAt,
    this.lastPacketFrom = '',
    this.broadcastAddress = '',
    this.wakeOnMagicPacket,
    this.wakeOnPattern,
    this.shutdownWakeOnLan,
    this.wakeArmed,
    this.fastStartupEnabled,
    this.autoSignOnBlocked,
    this.bitLockerPreBootPin,
    this.autoStartEnabled = false,
    this.standbySupported = false,
    this.hibernateSupported = false,
  });

  final String adapterName;

  /// The adapter that would receive the packet is Wi-Fi. Wake-on-Wireless is
  /// rare enough in practice that this is treated as a blocker, not a note.
  final bool wirelessAdapter;

  final String macAddress;
  final String ipAddress;

  /// Whether the machine is watching for its own wake packets right now.
  final bool probeListening;

  /// When a wake packet for this machine last arrived **while it was awake**.
  ///
  /// Nothing is observed while asleep — the app is not running — so this
  /// answers "can the packet reach this machine at all", not "did the last
  /// wake attempt arrive".
  final DateTime? lastPacketAt;

  /// The address that sent it, which should be the phone's.
  final String lastPacketFrom;

  /// Directed broadcast for the machine's subnet, e.g. 192.168.1.255.
  final String broadcastAddress;

  final bool? wakeOnMagicPacket;

  /// "Wake on Pattern Match": the card wakes the machine for ordinary network
  /// traffic, not just a magic packet. A home network broadcasts constantly,
  /// so leaving this on means the machine never stays asleep.
  final bool? wakeOnPattern;

  /// Some drivers gate waking from a full shutdown separately from waking
  /// from sleep. Null where the driver has no such setting at all.
  final bool? shutdownWakeOnLan;

  /// Windows is letting this device wake the machine. Supporting magic
  /// packets is not the same thing, so both have to be true.
  final bool? wakeArmed;

  final bool? fastStartupEnabled;

  /// Policy blocks Windows from signing back in after a restart.
  final bool? autoSignOnBlocked;

  final bool? bitLockerPreBootPin;

  /// Whether the app will start itself after the machine boots. Without this
  /// the machine can wake and still look offline, because nothing reports in.
  final bool autoStartEnabled;

  final bool standbySupported;
  final bool hibernateSupported;

  /// Returns a copy carrying what the packet listener has observed.
  ///
  /// Narrow on purpose: the rest of this object is read once and cached, while
  /// these three change whenever the phone taps wake.
  WakeDiagnostics withProbe({
    required bool probeListening,
    DateTime? lastPacketAt,
    String lastPacketFrom = '',
  }) {
    return WakeDiagnostics(
      adapterName: adapterName,
      wirelessAdapter: wirelessAdapter,
      macAddress: macAddress,
      ipAddress: ipAddress,
      probeListening: probeListening,
      lastPacketAt: lastPacketAt,
      lastPacketFrom: lastPacketFrom,
      broadcastAddress: broadcastAddress,
      wakeOnMagicPacket: wakeOnMagicPacket,
      wakeOnPattern: wakeOnPattern,
      shutdownWakeOnLan: shutdownWakeOnLan,
      wakeArmed: wakeArmed,
      fastStartupEnabled: fastStartupEnabled,
      autoSignOnBlocked: autoSignOnBlocked,
      bitLockerPreBootPin: bitLockerPreBootPin,
      autoStartEnabled: autoStartEnabled,
      standbySupported: standbySupported,
      hibernateSupported: hibernateSupported,
    );
  }

  /// There is at least an address to aim a packet at.
  bool get canAttemptWake => macAddress.trim().isNotEmpty;

  /// Waking from sleep looks possible on this machine.
  ///
  /// Wireless is not disqualifying on its own: plenty of cards listen for
  /// magic packets while the machine sleeps. What matters is whether this
  /// card does and whether Windows lets it.
  bool get canWakeFromSleep =>
      canAttemptWake &&
      wakeOnMagicPacket == true &&
      wakeArmed != false &&
      (standbySupported || hibernateSupported);

  /// Waking from a full shutdown asks for more: the card has to stay powered
  /// after the machine is off, which Fast Startup and a wireless link both
  /// tend to prevent.
  bool get canWakeFromShutdown =>
      canWakeFromSleep &&
      fastStartupEnabled != true &&
      shutdownWakeOnLan != false &&
      !wirelessAdapter;

  /// Everything that will keep a wake attempt from working, worst first.
  ///
  /// Ordered so the first entry is the one worth acting on: a pre-boot PIN
  /// makes the rest academic, and an agent that never starts makes a
  /// successful wake invisible.
  List<WakeBlocker> get blockers {
    final blockers = <WakeBlocker>[];

    if (bitLockerPreBootPin == true) {
      blockers.add(
        const WakeBlocker(
          title: 'BitLocker hỏi PIN trước khi khởi động',
          detail: 'Máy dừng trước cả Windows nên không có cách nào từ xa.',
          fix:
              'Chỉ khởi động lại được khi có người ở đó. Với một lần khởi '
              'động có kế hoạch, dùng manage-bde -protectors -disable '
              '-rebootcount 1 trước khi tắt.',
          fatal: true,
        ),
      );
    }

    if (!canAttemptWake) {
      blockers.add(
        const WakeBlocker(
          title: 'Chưa biết địa chỉ MAC của máy',
          detail:
              'Máy chưa gửi về địa chỉ card mạng nên không gửi gói '
              'đánh thức tới đâu được.',
          fix:
              'Mở app trên máy tính một lần khi máy đang bật để nó gửi '
              'thông tin này lên.',
          fatal: false,
        ),
      );
    }

    if (!autoStartEnabled) {
      blockers.add(
        const WakeBlocker(
          title: 'App không tự khởi động cùng Windows',
          detail:
              'Máy có bật lên thì điện thoại vẫn thấy offline, vì không '
              'có gì gửi tín hiệu.',
          fix:
              'Bật "Tự khởi động cùng Windows" trong Options > Điều khiển '
              'trên máy tính.',
          fatal: false,
        ),
      );
    }

    // Worth saying before anything about magic packets: a machine that wakes
    // itself seconds after sleeping makes the whole feature untestable, and
    // it looks like "sleep did not work" rather than a wake setting.
    if (wakeOnPattern == true) {
      blockers.add(
        WakeBlocker(
          title: 'Máy sẽ tự dậy ngay sau khi ngủ',
          detail:
              '$adapterName đang bật "Wake on Pattern Match", tức là bất '
              'kỳ lưu lượng mạng nào cũng đánh thức máy. Mạng nhà broadcast '
              'liên tục nên máy thường dậy lại sau vài giây.',
          fix:
              'Device Manager > card mạng > Power Management: chọn "Only '
              'allow a magic packet to wake the computer".',
          fatal: false,
        ),
      );
    }

    // Windows can report a wireless card as magic-packet capable and armed and
    // still never wake, because the radio is unpowered in sleep unless the
    // firmware keeps it alive. Measured on the test machine: every Windows
    // setting correct, keyboard wake working, magic packet ignored.
    if (wirelessAdapter && wakeOnMagicPacket == true && wakeArmed != false) {
      blockers.add(
        WakeBlocker(
          title: 'Đánh thức qua Wi-Fi còn phụ thuộc BIOS',
          detail: 'Windows báo $adapterName nghe được gói đánh thức, nhưng '
              'phần lớn laptop cắt điện radio Wi-Fi khi ngủ nên card không '
              'nghe được gì. Bàn phím đánh thức được mà điện thoại thì '
              'không, chính là dấu hiệu của việc này.',
          fix: 'Vào BIOS tìm "Wake on WLAN" (máy HP thường ở Advanced > '
              'Built-in Device Options) và bật lên. Không có tuỳ chọn đó thì '
              'phải cắm dây mạng mới đánh thức được từ xa.',
          fatal: false,
        ),
      );
    }

    if (wakeOnMagicPacket == false) {
      blockers.add(
        WakeBlocker(
          title: 'Card mạng đang tắt Wake on Magic Packet',
          detail: '$adapterName được cấu hình bỏ qua gói đánh thức.',
          fix:
              'Device Manager > card mạng > Advanced: đặt "Wake on Magic '
              'Packet" thành Enabled.',
          fatal: false,
        ),
      );
    } else if (wakeOnMagicPacket == null) {
      blockers.add(
        const WakeBlocker(
          title: 'Không đọc được cấu hình đánh thức của card mạng',
          detail:
              'Không rõ card mạng có nghe gói đánh thức hay không, nên '
              'thử vẫn đáng nhưng không chắc.',
          fix:
              'Kiểm tra tay trong Device Manager > card mạng > Advanced > '
              'Wake on Magic Packet.',
          fatal: false,
        ),
      );
    }

    if (wakeArmed == false) {
      blockers.add(
        WakeBlocker(
          title: 'Windows chưa cho card mạng đánh thức máy',
          detail: '$adapterName hỗ trợ nhưng đang không được phép đánh thức.',
          fix:
              'Device Manager > card mạng > Power Management: bật "Allow '
              'this device to wake the computer".',
          fatal: false,
        ),
      );
    }

    if (!standbySupported && !hibernateSupported) {
      blockers.add(
        const WakeBlocker(
          title: 'Máy không có trạng thái ngủ nào dùng được',
          detail:
              'Không ngủ được thì chỉ còn đánh thức từ trạng thái tắt '
              'hẳn, vốn nhiều card mạng không làm được.',
          fix: 'Kiểm tra powercfg /a trên máy và bật S3 trong BIOS nếu có.',
          fatal: false,
        ),
      );
    }

    // Not a failure so much as a boundary: say which button to use.
    if (canWakeFromSleep && !canWakeFromShutdown) {
      blockers.add(
        WakeBlocker(
          title: 'Chỉ đánh thức được từ trạng thái Ngủ',
          detail: _shutdownWakeDetail,
          fix: 'Dùng nút Ngủ thay cho Tắt máy khi còn muốn đánh thức từ xa.',
          fatal: false,
        ),
      );
    }

    if (autoSignOnBlocked == true) {
      blockers.add(
        const WakeBlocker(
          title: 'Chính sách máy chặn tự đăng nhập lại',
          detail:
              'Sau khi khởi động lại, Windows sẽ đứng ở màn hình khóa và '
              'app không chạy cho tới khi có người nhập PIN.',
          fix:
              'Bật "Dùng thông tin đăng nhập để tự động hoàn tất thiết lập" '
              'trong Settings > Accounts > Sign-in options.',
          fatal: false,
        ),
      );
    }

    return blockers;
  }

  String get _shutdownWakeDetail {
    if (wirelessAdapter) {
      return 'Máy đang nối bằng Wi-Fi ($adapterName), và tắt hẳn là card '
          'mất điện nên không nghe được gói đánh thức nữa.';
    }
    if (shutdownWakeOnLan == false) {
      return 'Driver card mạng đang tắt "Shutdown Wake-On-Lan".';
    }
    return 'Fast Startup đang bật, nên tắt máy thường làm card mạng mất điện.';
  }

  Map<String, Object?> toJson() {
    return {
      'adapterName': adapterName,
      'wirelessAdapter': wirelessAdapter,
      'macAddress': macAddress,
      'ipAddress': ipAddress,
      'probeListening': probeListening,
      'lastPacketAt': lastPacketAt?.toUtc().toIso8601String(),
      'lastPacketFrom': lastPacketFrom,
      'broadcastAddress': broadcastAddress,
      'wakeOnMagicPacket': wakeOnMagicPacket,
      'wakeOnPattern': wakeOnPattern,
      'shutdownWakeOnLan': shutdownWakeOnLan,
      'wakeArmed': wakeArmed,
      'fastStartupEnabled': fastStartupEnabled,
      'autoSignOnBlocked': autoSignOnBlocked,
      'bitLockerPreBootPin': bitLockerPreBootPin,
      'autoStartEnabled': autoStartEnabled,
      'standbySupported': standbySupported,
      'hibernateSupported': hibernateSupported,
    };
  }

  factory WakeDiagnostics.fromJson(Map<String, Object?> json) {
    return WakeDiagnostics(
      adapterName: json['adapterName']?.toString() ?? '',
      wirelessAdapter: json['wirelessAdapter'] == true,
      macAddress: json['macAddress']?.toString() ?? '',
      ipAddress: json['ipAddress']?.toString() ?? '',
      probeListening: json['probeListening'] == true,
      lastPacketAt: DateTime.tryParse(json['lastPacketAt']?.toString() ?? '')
          ?.toLocal(),
      lastPacketFrom: json['lastPacketFrom']?.toString() ?? '',
      broadcastAddress: json['broadcastAddress']?.toString() ?? '',
      wakeOnMagicPacket: _tristate(json['wakeOnMagicPacket']),
      wakeOnPattern: _tristate(json['wakeOnPattern']),
      shutdownWakeOnLan: _tristate(json['shutdownWakeOnLan']),
      wakeArmed: _tristate(json['wakeArmed']),
      fastStartupEnabled: _tristate(json['fastStartupEnabled']),
      autoSignOnBlocked: _tristate(json['autoSignOnBlocked']),
      bitLockerPreBootPin: _tristate(json['bitLockerPreBootPin']),
      autoStartEnabled: json['autoStartEnabled'] == true,
      standbySupported: json['standbySupported'] == true,
      hibernateSupported: json['hibernateSupported'] == true,
    );
  }
}

/// Keeps "not readable" distinct from "off" across the wire.
bool? _tristate(Object? value) {
  if (value is bool) return value;
  return null;
}
