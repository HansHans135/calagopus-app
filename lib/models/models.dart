/// Models for the wider client API surface (files, backups, databases,
/// schedules, subusers, allocations, account resources, groups).
library;

class Paginated<T> {
  final int total;
  final int page;
  final int perPage;
  final List<T> data;

  Paginated({
    required this.total,
    required this.page,
    required this.perPage,
    required this.data,
  });

  factory Paginated.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) =>
      Paginated(
        total: json['total'] as int? ?? 0,
        page: json['page'] as int? ?? 1,
        perPage: json['per_page'] as int? ?? 25,
        data: (json['data'] as List? ?? const [])
            .map((e) => parse(e as Map<String, dynamic>))
            .toList(),
      );

  bool get hasMore => page * perPage < total;
}

class FileEntry {
  final String name;
  final String mode;
  final String modeBits;
  final int size;
  final bool editable;
  final bool directory;
  final bool file;
  final bool symlink;
  final String mime;
  final DateTime? modified;

  FileEntry({
    required this.name,
    required this.mode,
    required this.modeBits,
    required this.size,
    required this.editable,
    required this.directory,
    required this.file,
    required this.symlink,
    required this.mime,
    this.modified,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
        name: json['name'] as String? ?? '',
        mode: json['mode'] as String? ?? '',
        modeBits: json['mode_bits'] as String? ?? '',
        size: (json['size'] as num? ?? 0).toInt(),
        editable: json['editable'] as bool? ?? false,
        directory: json['directory'] as bool? ?? false,
        file: json['file'] as bool? ?? false,
        symlink: json['symlink'] as bool? ?? false,
        mime: json['mime'] as String? ?? '',
        modified: DateTime.tryParse(json['modified'] as String? ?? ''),
      );

  bool get isArchive =>
      mime.contains('zip') ||
      mime.contains('tar') ||
      mime.contains('gzip') ||
      mime.contains('7z') ||
      mime.contains('compress');
}

class Backup {
  final String uuid;
  final String name;
  final bool isSuccessful;
  final bool isLocked;
  final int bytes;
  final int files;
  final DateTime? completed;
  final DateTime? created;

  Backup({
    required this.uuid,
    required this.name,
    required this.isSuccessful,
    required this.isLocked,
    required this.bytes,
    required this.files,
    this.completed,
    this.created,
  });

  factory Backup.fromJson(Map<String, dynamic> json) => Backup(
        uuid: json['uuid'] as String,
        name: json['name'] as String? ?? '',
        isSuccessful: json['is_successful'] as bool? ?? false,
        isLocked: json['is_locked'] as bool? ?? false,
        bytes: (json['bytes'] as num? ?? 0).toInt(),
        files: (json['files'] as num? ?? 0).toInt(),
        completed: DateTime.tryParse(json['completed'] as String? ?? ''),
        created: DateTime.tryParse(json['created'] as String? ?? ''),
      );
}

class ServerDatabase {
  final String uuid;
  final String type;
  final String host;
  final int port;
  final String name;
  final bool isLocked;
  final String username;
  final String? password;

  ServerDatabase({
    required this.uuid,
    required this.type,
    required this.host,
    required this.port,
    required this.name,
    required this.isLocked,
    required this.username,
    this.password,
  });

  factory ServerDatabase.fromJson(Map<String, dynamic> json) =>
      ServerDatabase(
        uuid: json['uuid'] as String,
        type: json['type'] as String? ?? '',
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        isLocked: json['is_locked'] as bool? ?? false,
        username: json['username'] as String? ?? '',
        password: json['password'] as String?,
      );
}

class DatabaseHost {
  final String uuid;
  final String name;
  final String type;
  final String host;
  final int port;
  final bool maintenanceEnabled;

  DatabaseHost({
    required this.uuid,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.maintenanceEnabled,
  });

  factory DatabaseHost.fromJson(Map<String, dynamic> json) => DatabaseHost(
        uuid: json['uuid'] as String,
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? '',
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 0,
        maintenanceEnabled: json['maintenance_enabled'] as bool? ?? false,
      );
}

class Schedule {
  final String uuid;
  final String name;
  final bool enabled;
  final List<dynamic> triggers;
  final Map<String, dynamic> condition;
  final DateTime? lastRun;
  final DateTime? lastFailure;

  Schedule({
    required this.uuid,
    required this.name,
    required this.enabled,
    required this.triggers,
    required this.condition,
    this.lastRun,
    this.lastFailure,
  });

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
        uuid: json['uuid'] as String,
        name: json['name'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? false,
        triggers: json['triggers'] as List? ?? const [],
        condition:
            json['condition'] as Map<String, dynamic>? ?? const {'type': 'none'},
        lastRun: DateTime.tryParse(json['last_run'] as String? ?? ''),
        lastFailure:
            DateTime.tryParse(json['last_failure'] as String? ?? ''),
      );
}

class ScheduleStep {
  final String uuid;
  final Map<String, dynamic> action;
  final int order;

  ScheduleStep({required this.uuid, required this.action, required this.order});

  factory ScheduleStep.fromJson(Map<String, dynamic> json) => ScheduleStep(
        uuid: json['uuid'] as String,
        action: json['action'] as Map<String, dynamic>? ?? const {},
        order: json['order'] as int? ?? 0,
      );
}

class Subuser {
  final String userUuid;
  final String username;
  final String? avatar;
  final bool totpEnabled;
  final List<String> permissions;
  final List<String> ignoredFiles;

  Subuser({
    required this.userUuid,
    required this.username,
    this.avatar,
    required this.totpEnabled,
    required this.permissions,
    required this.ignoredFiles,
  });

  factory Subuser.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    return Subuser(
      userUuid: user['uuid'] as String? ?? '',
      username: user['username'] as String? ?? '',
      avatar: user['avatar'] as String?,
      totpEnabled: user['totp_enabled'] as bool? ?? false,
      permissions:
          (json['permissions'] as List? ?? const []).cast<String>(),
      ignoredFiles:
          (json['ignored_files'] as List? ?? const []).cast<String>(),
    );
  }
}

class StartupVariable {
  final String name;
  final String? description;
  final String envVariable;
  final String? defaultValue;
  final String value;
  final bool isEditable;
  final bool isSecret;
  final List<String> rules;

  StartupVariable({
    required this.name,
    this.description,
    required this.envVariable,
    this.defaultValue,
    required this.value,
    required this.isEditable,
    required this.isSecret,
    required this.rules,
  });

  factory StartupVariable.fromJson(Map<String, dynamic> json) =>
      StartupVariable(
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        envVariable: json['env_variable'] as String? ?? '',
        defaultValue: json['default_value'] as String?,
        value: json['value'] as String? ?? '',
        isEditable: json['is_editable'] as bool? ?? false,
        isSecret: json['is_secret'] as bool? ?? false,
        rules: (json['rules'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class ActivityEntry {
  final String event;
  final String? ip;
  final dynamic data;
  final bool isApi;
  final String? username;
  final DateTime? created;

  ActivityEntry({
    required this.event,
    this.ip,
    this.data,
    required this.isApi,
    this.username,
    this.created,
  });

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
        event: json['event'] as String? ?? '',
        ip: json['ip'] as String?,
        data: json['data'],
        isApi: json['is_api'] as bool? ?? false,
        username: (json['user'] is Map)
            ? (json['user']['username'] as String?)
            : null,
        created: DateTime.tryParse(json['created'] as String? ?? ''),
      );
}

class ApiKeyInfo {
  final String uuid;
  final String name;
  final String keyStart;
  final List<String> allowedIps;
  final DateTime? lastUsed;
  final DateTime? expires;
  final DateTime? created;

  ApiKeyInfo({
    required this.uuid,
    required this.name,
    required this.keyStart,
    required this.allowedIps,
    this.lastUsed,
    this.expires,
    this.created,
  });

  factory ApiKeyInfo.fromJson(Map<String, dynamic> json) => ApiKeyInfo(
        uuid: json['uuid'] as String,
        name: json['name'] as String? ?? '',
        keyStart: json['key_start'] as String? ?? '',
        allowedIps:
            (json['allowed_ips'] as List? ?? const []).cast<String>(),
        lastUsed: DateTime.tryParse(json['last_used'] as String? ?? ''),
        expires: DateTime.tryParse(json['expires'] as String? ?? ''),
        created: DateTime.tryParse(json['created'] as String? ?? ''),
      );
}

class SshKey {
  final String uuid;
  final String name;
  final String fingerprint;
  final DateTime? created;

  SshKey({
    required this.uuid,
    required this.name,
    required this.fingerprint,
    this.created,
  });

  factory SshKey.fromJson(Map<String, dynamic> json) => SshKey(
        uuid: json['uuid'] as String,
        name: json['name'] as String? ?? '',
        fingerprint: json['fingerprint'] as String? ?? '',
        created: DateTime.tryParse(json['created'] as String? ?? ''),
      );
}

class SecurityKey {
  final String uuid;
  final String name;
  final DateTime? lastUsed;
  final DateTime? created;

  SecurityKey({
    required this.uuid,
    required this.name,
    this.lastUsed,
    this.created,
  });

  factory SecurityKey.fromJson(Map<String, dynamic> json) => SecurityKey(
        uuid: json['uuid'] as String,
        name: json['name'] as String? ?? '',
        lastUsed: DateTime.tryParse(json['last_used'] as String? ?? ''),
        created: DateTime.tryParse(json['created'] as String? ?? ''),
      );
}

class UserSession {
  final String uuid;
  final String ip;
  final String userAgent;
  final bool isUsing;
  final DateTime? lastUsed;

  UserSession({
    required this.uuid,
    required this.ip,
    required this.userAgent,
    required this.isUsing,
    this.lastUsed,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        uuid: json['uuid'] as String,
        ip: json['ip'] as String? ?? '',
        userAgent: json['user_agent'] as String? ?? '',
        isUsing: json['is_using'] as bool? ?? false,
        lastUsed: DateTime.tryParse(json['last_used'] as String? ?? ''),
      );
}

class CommandSnippet {
  final String uuid;
  final String name;
  final List<String> eggs;
  final String command;

  CommandSnippet({
    required this.uuid,
    required this.name,
    required this.eggs,
    required this.command,
  });

  factory CommandSnippet.fromJson(Map<String, dynamic> json) =>
      CommandSnippet(
        uuid: json['uuid'] as String,
        name: json['name'] as String? ?? '',
        eggs: (json['eggs'] as List? ?? const []).cast<String>(),
        command: json['command'] as String? ?? '',
      );
}

class OAuthLink {
  final String uuid;
  final String providerName;
  final String identifier;
  final bool userManageable;
  final DateTime? lastUsed;

  OAuthLink({
    required this.uuid,
    required this.providerName,
    required this.identifier,
    required this.userManageable,
    this.lastUsed,
  });

  factory OAuthLink.fromJson(Map<String, dynamic> json) {
    final provider =
        json['oauth_provider'] as Map<String, dynamic>? ?? const {};
    return OAuthLink(
      uuid: json['uuid'] as String,
      providerName: provider['name'] as String? ?? '',
      identifier: json['identifier'] as String? ?? '',
      userManageable: provider['user_manageable'] as bool? ?? false,
      lastUsed: DateTime.tryParse(json['last_used'] as String? ?? ''),
    );
  }
}

class ServerGroup {
  final String uuid;
  final String name;
  final int order;
  final List<String> serverOrder;

  ServerGroup({
    required this.uuid,
    required this.name,
    required this.order,
    required this.serverOrder,
  });

  factory ServerGroup.fromJson(Map<String, dynamic> json) => ServerGroup(
        uuid: json['uuid'] as String,
        name: json['name'] as String? ?? '',
        order: json['order'] as int? ?? 0,
        serverOrder:
            (json['server_order'] as List? ?? const []).cast<String>(),
      );
}

class ServerMount {
  final String uuid;
  final String name;
  final String? description;
  final String target;
  final bool readOnly;

  ServerMount({
    required this.uuid,
    required this.name,
    this.description,
    required this.target,
    required this.readOnly,
  });

  factory ServerMount.fromJson(Map<String, dynamic> json) => ServerMount(
        uuid: json['uuid'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        target: json['target'] as String? ?? '',
        readOnly: json['read_only'] as bool? ?? false,
      );
}

class Announcement {
  final String uuid;
  final String type;
  final String title;
  final String content;

  Announcement({
    required this.uuid,
    required this.type,
    required this.title,
    required this.content,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
        uuid: json['uuid'] as String? ?? '',
        type: json['type'] as String? ?? 'info',
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
      );
}

String formatDateTime(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
