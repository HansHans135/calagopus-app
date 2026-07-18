class Account {
  final String username;
  final String email;
  final bool admin;

  Account({required this.username, required this.email, required this.admin});

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        username: json['username'] as String? ?? '',
        email: json['email'] as String? ?? '',
        admin: json['admin'] as bool? ?? false,
      );
}

class ServerAllocation {
  final String uuid;
  final String ip;
  final String? ipAlias;
  final int port;
  final String? notes;
  final bool isPrimary;

  ServerAllocation({
    this.uuid = '',
    required this.ip,
    this.ipAlias,
    required this.port,
    this.notes,
    this.isPrimary = false,
  });

  factory ServerAllocation.fromJson(Map<String, dynamic> json) =>
      ServerAllocation(
        uuid: json['uuid'] as String? ?? '',
        ip: json['ip'] as String? ?? '',
        ipAlias: json['ip_alias'] as String?,
        port: json['port'] as int? ?? 0,
        notes: json['notes'] as String?,
        isPrimary: json['is_primary'] as bool? ?? false,
      );

  String get display => '${ipAlias ?? ip}:$port';
}

class Server {
  final String uuid;
  final String uuidShort;
  final String name;
  final String? description;
  final String? status;
  final bool isOwner;
  final bool isSuspended;
  final bool isTransferring;
  final String nodeName;
  final String locationName;
  final ServerAllocation? allocation;
  final Map<String, dynamic> limits;
  final Map<String, dynamic> featureLimits;
  final List<String> permissions;
  final String sftpHost;
  final int sftpPort;
  final String startup;
  final String image;
  final String eggUuid;
  final String eggName;

  Server({
    required this.uuid,
    required this.uuidShort,
    required this.name,
    this.description,
    this.status,
    required this.isOwner,
    required this.isSuspended,
    required this.isTransferring,
    required this.nodeName,
    required this.locationName,
    this.allocation,
    required this.limits,
    required this.featureLimits,
    required this.permissions,
    required this.sftpHost,
    required this.sftpPort,
    required this.startup,
    required this.image,
    required this.eggUuid,
    required this.eggName,
  });

  factory Server.fromJson(Map<String, dynamic> json) {
    final egg = json['egg'] as Map<String, dynamic>? ?? const {};
    return Server(
      uuid: json['uuid'] as String,
      uuidShort: json['uuid_short'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      status: json['status'] as String?,
      isOwner: json['is_owner'] as bool? ?? false,
      isSuspended: json['is_suspended'] as bool? ?? false,
      isTransferring: json['is_transferring'] as bool? ?? false,
      nodeName: json['node_name'] as String? ?? '',
      locationName: json['location_name'] as String? ?? '',
      allocation: json['allocation'] == null
          ? null
          : ServerAllocation.fromJson(
              json['allocation'] as Map<String, dynamic>),
      limits: json['limits'] as Map<String, dynamic>? ?? const {},
      featureLimits:
          json['feature_limits'] as Map<String, dynamic>? ?? const {},
      permissions:
          (json['permissions'] as List? ?? const []).cast<String>(),
      sftpHost: json['sftp_host'] as String? ?? '',
      sftpPort: json['sftp_port'] as int? ?? 2022,
      startup: json['startup'] as String? ?? '',
      image: json['image'] as String? ?? '',
      eggUuid: egg['uuid'] as String? ?? '',
      eggName: egg['name'] as String? ?? '',
    );
  }
}

class ServerPage {
  final int total;
  final int page;
  final int perPage;
  final List<Server> servers;

  ServerPage({
    required this.total,
    required this.page,
    required this.perPage,
    required this.servers,
  });

  factory ServerPage.fromJson(Map<String, dynamic> json) => ServerPage(
        total: json['total'] as int? ?? 0,
        page: json['page'] as int? ?? 1,
        perPage: json['per_page'] as int? ?? 25,
        servers: (json['data'] as List? ?? const [])
            .map((e) => Server.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  bool get hasMore => page * perPage < total;
}

class ResourceUsage {
  final int memoryBytes;
  final int memoryLimitBytes;
  final int diskBytes;
  final String state;
  final int rxBytes;
  final int txBytes;
  final double cpuAbsolute;
  final int uptimeMs;

  ResourceUsage({
    required this.memoryBytes,
    required this.memoryLimitBytes,
    required this.diskBytes,
    required this.state,
    required this.rxBytes,
    required this.txBytes,
    required this.cpuAbsolute,
    required this.uptimeMs,
  });

  factory ResourceUsage.fromJson(Map<String, dynamic> json) {
    final network = json['network'] as Map<String, dynamic>? ?? const {};
    return ResourceUsage(
      memoryBytes: (json['memory_bytes'] as num? ?? 0).toInt(),
      memoryLimitBytes: (json['memory_limit_bytes'] as num? ?? 0).toInt(),
      diskBytes: (json['disk_bytes'] as num? ?? 0).toInt(),
      state: json['state'] as String? ?? 'offline',
      rxBytes: (network['rx_bytes'] as num? ?? 0).toInt(),
      txBytes: (network['tx_bytes'] as num? ?? 0).toInt(),
      cpuAbsolute: (json['cpu_absolute'] as num? ?? 0).toDouble(),
      uptimeMs: (json['uptime'] as num? ?? 0).toInt(),
    );
  }
}

String formatBytes(num bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

String formatUptime(int ms) {
  final d = Duration(milliseconds: ms);
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  if (days > 0) return '${days}d ${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}
