import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../models/server.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'API $statusCode: $message';
}

/// HTTP client for the Calagopus panel client API.
///
/// Authentication uses `Authorization: Bearer <api key>`.
class CalagopusClient {
  final String baseUrl;
  final String apiKey;
  final http.Client _http;

  CalagopusClient({required String baseUrl, required this.apiKey})
      : baseUrl = _normalizeBaseUrl(baseUrl),
        _http = http.Client();

  static String _normalizeBaseUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Map<String, String> get _headers => {
        'Authorization':
            apiKey.startsWith('Bearer ') ? apiKey : 'Bearer $apiKey',
        'Accept': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<http.Response> _raw(
    String method,
    String path, {
    Map<String, String>? query,
    Object? jsonBody,
    String? textBody,
  }) async {
    final req = http.Request(method, _uri(path, query));
    req.headers.addAll(_headers);
    if (jsonBody != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(jsonBody);
    } else if (textBody != null) {
      req.headers['Content-Type'] = 'text/plain';
      req.body = textBody;
    }
    final streamed =
        await _http.send(req).timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 200 && res.statusCode < 300) return res;

    String message = res.reasonPhrase ?? 'Request failed';
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map && decoded['errors'] is List) {
        message = (decoded['errors'] as List).join('; ');
      } else if (decoded is Map && decoded['error'] != null) {
        message = decoded['error'].toString();
      }
    } catch (_) {}
    throw ApiException(res.statusCode, message);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? textBody,
  }) async {
    final res = await _raw(method, path,
        query: query, jsonBody: body, textBody: textBody);
    if (res.body.isEmpty) return const {};
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
  }

  /// Plain-text GET (file contents, logs).
  Future<String> getText(String path, {Map<String, String>? query}) async {
    final res = await _raw('GET', path, query: query);
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  static Map<String, String> pageQuery(int page, int perPage,
          [String? search]) =>
      {
        'page': '$page',
        'per_page': '$perPage',
        if (search != null && search.isNotEmpty) 'search': search,
      };

  void close() => _http.close();

  // ───────────────────────── Account ─────────────────────────

  Future<Account> getAccount() async {
    final json = await _request('GET', '/api/client/account');
    return Account.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getAccountRaw() async {
    final json = await _request('GET', '/api/client/account');
    return json['user'] as Map<String, dynamic>;
  }

  Future<void> updateAccount(Map<String, dynamic> fields) =>
      _request('PATCH', '/api/client/account', body: fields);

  Future<void> updateEmail(String email, String password) => _request(
      'PUT', '/api/client/account/email',
      body: {'email': email, 'password': password});

  Future<void> updatePassword(String current, String newPassword) => _request(
      'PUT', '/api/client/account/password',
      body: {'password': current, 'new_password': newPassword});

  Future<Paginated<ActivityEntry>> getAccountActivity(
      {int page = 1, int perPage = 25, String? search}) async {
    final json = await _request('GET', '/api/client/account/activity',
        query: pageQuery(page, perPage, search));
    return Paginated.fromJson(
        json['activities'] as Map<String, dynamic>, ActivityEntry.fromJson);
  }

  // Two-factor

  Future<({String otpUrl, String secret})> getTwoFactorSetup() async {
    final json = await _request('GET', '/api/client/account/two-factor');
    return (
      otpUrl: json['otp_url'] as String,
      secret: json['secret'] as String
    );
  }

  Future<List<String>> enableTwoFactor(String code, String password) async {
    final json = await _request('POST', '/api/client/account/two-factor',
        body: {'code': code, 'password': password});
    return (json['recovery_codes'] as List? ?? const []).cast<String>();
  }

  Future<void> disableTwoFactor(String code, String password) =>
      _request('DELETE', '/api/client/account/two-factor',
          body: {'code': code, 'password': password});

  // API keys

  Future<Paginated<ApiKeyInfo>> getApiKeys(
      {int page = 1, int perPage = 25, String? search}) async {
    final json = await _request('GET', '/api/client/account/api-keys',
        query: pageQuery(page, perPage, search));
    return Paginated.fromJson(
        json['api_keys'] as Map<String, dynamic>, ApiKeyInfo.fromJson);
  }

  Future<String> createApiKey({
    required String name,
    List<String> allowedIps = const [],
    List<String> userPermissions = const [],
    List<String> adminPermissions = const [],
    List<String> serverPermissions = const [],
  }) async {
    final json =
        await _request('POST', '/api/client/account/api-keys', body: {
      'name': name,
      'allowed_ips': allowedIps,
      'user_permissions': userPermissions,
      'admin_permissions': adminPermissions,
      'server_permissions': serverPermissions,
    });
    return json['key'] as String;
  }

  Future<void> deleteApiKey(String uuid) =>
      _request('DELETE', '/api/client/account/api-keys/$uuid');

  Future<String> recreateApiKey(String uuid) async {
    final json = await _request(
        'POST', '/api/client/account/api-keys/$uuid/recreate');
    return json['key'] as String;
  }

  // SSH keys

  Future<Paginated<SshKey>> getSshKeys(
      {int page = 1, int perPage = 25, String? search}) async {
    final json = await _request('GET', '/api/client/account/ssh-keys',
        query: pageQuery(page, perPage, search));
    return Paginated.fromJson(
        json['ssh_keys'] as Map<String, dynamic>, SshKey.fromJson);
  }

  Future<void> createSshKey(String name, String publicKey) =>
      _request('POST', '/api/client/account/ssh-keys',
          body: {'name': name, 'public_key': publicKey});

  Future<int> importSshKeys(String provider, String username) async {
    final json = await _request(
        'POST', '/api/client/account/ssh-keys/import',
        body: {'provider': provider, 'username': username});
    return (json['ssh_keys'] as List? ?? const []).length;
  }

  Future<void> deleteSshKey(String uuid) =>
      _request('DELETE', '/api/client/account/ssh-keys/$uuid');

  // Security keys

  Future<Paginated<SecurityKey>> getSecurityKeys(
      {int page = 1, int perPage = 25}) async {
    final json = await _request('GET', '/api/client/account/security-keys',
        query: pageQuery(page, perPage));
    return Paginated.fromJson(
        json['security_keys'] as Map<String, dynamic>,
        SecurityKey.fromJson);
  }

  Future<void> renameSecurityKey(String uuid, String name) => _request(
      'PATCH', '/api/client/account/security-keys/$uuid',
      body: {'name': name});

  Future<void> deleteSecurityKey(String uuid) =>
      _request('DELETE', '/api/client/account/security-keys/$uuid');

  // Sessions

  Future<Paginated<UserSession>> getSessions(
      {int page = 1, int perPage = 25}) async {
    final json = await _request('GET', '/api/client/account/sessions',
        query: pageQuery(page, perPage));
    return Paginated.fromJson(
        json['sessions'] as Map<String, dynamic>, UserSession.fromJson);
  }

  Future<void> deleteSession(String uuid) =>
      _request('DELETE', '/api/client/account/sessions/$uuid');

  // Command snippets

  Future<Paginated<CommandSnippet>> getCommandSnippets(
      {int page = 1, int perPage = 50, String? search}) async {
    final json = await _request(
        'GET', '/api/client/account/command-snippets',
        query: pageQuery(page, perPage, search));
    return Paginated.fromJson(
        json['command_snippets'] as Map<String, dynamic>,
        CommandSnippet.fromJson);
  }

  Future<void> createCommandSnippet(
          String name, String command, List<String> eggs) =>
      _request('POST', '/api/client/account/command-snippets',
          body: {'name': name, 'command': command, 'eggs': eggs});

  Future<void> updateCommandSnippet(
          String uuid, String name, String command) =>
      _request('PATCH', '/api/client/account/command-snippets/$uuid',
          body: {'name': name, 'command': command});

  Future<void> deleteCommandSnippet(String uuid) =>
      _request('DELETE', '/api/client/account/command-snippets/$uuid');

  Future<List<CommandSnippet>> getEggCommandSnippets(String eggUuid) async {
    final json = await _request(
        'GET', '/api/client/servers/eggs/$eggUuid/command-snippets');
    return (json['command_snippets'] as List? ?? const [])
        .map((e) => CommandSnippet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // OAuth links

  Future<Paginated<OAuthLink>> getOAuthLinks(
      {int page = 1, int perPage = 25}) async {
    final json = await _request('GET', '/api/client/account/oauth-links',
        query: pageQuery(page, perPage));
    return Paginated.fromJson(
        json['oauth_links'] as Map<String, dynamic>, OAuthLink.fromJson);
  }

  Future<void> deleteOAuthLink(String uuid) =>
      _request('DELETE', '/api/client/account/oauth-links/$uuid');

  /// Permission catalog: {category: {permission: description}} per scope.
  Future<Map<String, dynamic>> getPermissions() =>
      _request('GET', '/api/client/permissions');

  // ─────────────────────── Server groups ───────────────────────

  Future<List<ServerGroup>> getServerGroups() async {
    final json = await _request('GET', '/api/client/servers/groups');
    return (json['server_groups'] as List? ?? const [])
        .map((e) => ServerGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createServerGroup(String name, List<String> serverOrder) =>
      _request('POST', '/api/client/servers/groups',
          body: {'name': name, 'server_order': serverOrder});

  Future<void> updateServerGroup(String uuid, String name,
          List<String> serverOrder) =>
      _request('PATCH', '/api/client/servers/groups/$uuid',
          body: {'name': name, 'server_order': serverOrder});

  Future<void> deleteServerGroup(String uuid) =>
      _request('DELETE', '/api/client/servers/groups/$uuid');

  // ───────────────────────── Servers ─────────────────────────

  Future<ServerPage> getServers({
    int page = 1,
    int perPage = 25,
    String? search,
    bool other = false,
  }) async {
    final json = await _request('GET', '/api/client/servers', query: {
      ...pageQuery(page, perPage, search),
      'other': '$other',
    });
    return ServerPage.fromJson(json['servers'] as Map<String, dynamic>);
  }

  Future<Server> getServer(String uuid) async {
    final json = await _request('GET', '/api/client/servers/$uuid');
    return Server.fromJson(json['server'] as Map<String, dynamic>);
  }

  Future<ResourceUsage> getResources(String serverUuid) async {
    final json =
        await _request('GET', '/api/client/servers/$serverUuid/resources');
    return ResourceUsage.fromJson(json['resources'] as Map<String, dynamic>);
  }

  Future<void> sendPowerAction(String serverUuid, String action) async {
    await _request('POST', '/api/client/servers/$serverUuid/power',
        body: {'action': action});
  }

  Future<({String token, String url})> getWebsocketDetails(
      String serverUuid) async {
    final json =
        await _request('GET', '/api/client/servers/$serverUuid/websocket');
    return (token: json['token'] as String, url: json['url'] as String);
  }

  Future<void> sendCommand(String serverUuid, String command) async {
    await _request('POST', '/api/client/servers/$serverUuid/command',
        body: {'command': command});
  }

  Future<List<Announcement>> getAnnouncements(String serverUuid) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/announcements');
    return (json['announcements'] as List? ?? const [])
        .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Paginated<ActivityEntry>> getServerActivity(String serverUuid,
      {int page = 1, int perPage = 25, String? search}) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/activity',
        query: pageQuery(page, perPage, search));
    return Paginated.fromJson(
        json['activities'] as Map<String, dynamic>, ActivityEntry.fromJson);
  }

  Future<String> getServerLogs(String serverUuid, {int lines = 250}) =>
      getText('/api/client/servers/$serverUuid/logs',
          query: {'lines': '$lines'});

  Future<String> getInstallLogs(String serverUuid) =>
      getText('/api/client/servers/$serverUuid/logs/install');

  // ───────────────────────── Files ─────────────────────────

  Future<({Paginated<FileEntry> entries, bool writable})> listFiles(
    String serverUuid, {
    required String directory,
    int page = 1,
    int perPage = 100,
  }) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/files/list',
        query: {
          'page': '$page',
          'per_page': '$perPage',
          'directory': directory,
        });
    return (
      entries: Paginated.fromJson(
          json['entries'] as Map<String, dynamic>, FileEntry.fromJson),
      writable: json['is_filesystem_writable'] as bool? ?? true,
    );
  }

  Future<String> getFileContents(String serverUuid, String path) =>
      getText('/api/client/servers/$serverUuid/files/contents',
          query: {'file': path, 'max_size': '${5 * 1024 * 1024}'});

  Future<void> writeFile(
          String serverUuid, String path, String content) =>
      _request('POST', '/api/client/servers/$serverUuid/files/write',
          query: {'file': path}, textBody: content);

  Future<void> createDirectory(
          String serverUuid, String root, String name) =>
      _request('POST',
          '/api/client/servers/$serverUuid/files/create-directory',
          body: {'root': root, 'name': name});

  Future<void> renameFiles(String serverUuid, String root,
          List<({String from, String to})> files) =>
      _request('PUT', '/api/client/servers/$serverUuid/files/rename',
          body: {
            'root': root,
            'files': [
              for (final f in files) {'from': f.from, 'to': f.to}
            ],
          });

  Future<void> copyFile(String serverUuid, String path) =>
      _request('POST', '/api/client/servers/$serverUuid/files/copy',
          body: {'path': path});

  Future<void> deleteFiles(
          String serverUuid, String root, List<String> files) =>
      _request('POST', '/api/client/servers/$serverUuid/files/delete',
          body: {'root': root, 'files': files});

  Future<void> compressFiles(String serverUuid, String root,
          List<String> files, String format, {String? name}) =>
      _request('POST', '/api/client/servers/$serverUuid/files/compress',
          body: {
            'root': root,
            'files': files,
            'format': format,
            if (name != null) 'name': name,
            'foreground': false,
          });

  Future<void> decompressFile(
          String serverUuid, String root, String file) =>
      _request('POST', '/api/client/servers/$serverUuid/files/decompress',
          body: {'root': root, 'file': file, 'foreground': false});

  Future<void> chmodFiles(String serverUuid, String root,
          List<({String file, String mode})> files) =>
      _request('PUT', '/api/client/servers/$serverUuid/files/chmod',
          body: {
            'root': root,
            'files': [
              for (final f in files) {'file': f.file, 'mode': f.mode}
            ],
          });

  /// Signed download URL for files or a whole directory archive.
  Future<String> getFilesDownloadUrl(
    String serverUuid, {
    required String root,
    List<String> files = const [],
    bool directory = false,
    String archiveFormat = 'tar_gz',
  }) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/files/download',
        query: {
          'root': root,
          'files': files.join(','),
          'directory': '$directory',
          'archive_format': archiveFormat,
        });
    return json['url'] as String;
  }

  Future<String> getFileUploadUrl(String serverUuid) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/files/upload');
    return json['url'] as String;
  }

  /// Uploads bytes to the signed wings upload URL.
  Future<void> uploadFile({
    required String uploadUrl,
    required String directory,
    required String filename,
    required List<int> bytes,
  }) async {
    final uri = Uri.parse(
        '$uploadUrl&directory=${Uri.encodeComponent(directory)}');
    final req = http.MultipartRequest('POST', uri);
    req.files.add(
        http.MultipartFile.fromBytes('files', bytes, filename: filename));
    final streamed =
        await req.send().timeout(const Duration(minutes: 10));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, '上傳失敗：${res.body}');
    }
  }

  Future<void> pullFile(String serverUuid, String root, String url,
          {String? name}) =>
      _request('POST', '/api/client/servers/$serverUuid/files/pull',
          body: {
            'root': root,
            'url': url,
            if (name != null && name.isNotEmpty) 'name': name,
            'foreground': false,
          });

  Future<List<FileEntry>> searchFiles(
      String serverUuid, String root, String query) async {
    final json = await _request(
        'POST', '/api/client/servers/$serverUuid/files/search',
        body: {
          'root': root,
          'path_filter': {
            'include': ['*$query*'],
            'exclude': [],
            'case_insensitive': true,
          },
        });
    return (json['entries'] as List? ?? const [])
        .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ───────────────────────── Backups ─────────────────────────

  Future<Paginated<Backup>> getBackups(String serverUuid,
      {int page = 1, int perPage = 25, String? search}) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/backups',
        query: pageQuery(page, perPage, search));
    return Paginated.fromJson(
        json['backups'] as Map<String, dynamic>, Backup.fromJson);
  }

  Future<void> createBackup(String serverUuid, {String? name}) =>
      _request('POST', '/api/client/servers/$serverUuid/backups', body: {
        if (name != null && name.isNotEmpty) 'name': name,
        'ignored_files': <String>[],
      });

  Future<void> updateBackup(String serverUuid, String backupUuid,
          {String? name, bool? locked}) =>
      _request(
          'PATCH', '/api/client/servers/$serverUuid/backups/$backupUuid',
          body: {
            if (name != null) 'name': name,
            if (locked != null) 'locked': locked,
          });

  Future<void> deleteBackup(String serverUuid, String backupUuid) =>
      _request(
          'DELETE', '/api/client/servers/$serverUuid/backups/$backupUuid');

  Future<String> getBackupDownloadUrl(
      String serverUuid, String backupUuid) async {
    final json = await _request('GET',
        '/api/client/servers/$serverUuid/backups/$backupUuid/download',
        query: {'archive_format': 'tar_gz'});
    return json['url'] as String;
  }

  Future<void> restoreBackup(String serverUuid, String backupUuid,
          {bool truncateDirectory = false}) =>
      _request('POST',
          '/api/client/servers/$serverUuid/backups/$backupUuid/restore',
          body: {'truncate_directory': truncateDirectory});

  // ──────────────────────── Databases ────────────────────────

  Future<Paginated<ServerDatabase>> getDatabases(String serverUuid,
      {int page = 1, int perPage = 25}) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/databases',
        query: {
          ...pageQuery(page, perPage),
          'include_password': 'true',
        });
    return Paginated.fromJson(
        json['databases'] as Map<String, dynamic>, ServerDatabase.fromJson);
  }

  Future<List<DatabaseHost>> getDatabaseHosts(String serverUuid) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/databases/hosts');
    return (json['database_hosts'] as List? ?? const [])
        .map((e) => DatabaseHost.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createDatabase(
          String serverUuid, String hostUuid, String name) =>
      _request('POST', '/api/client/servers/$serverUuid/databases',
          body: {'database_host_uuid': hostUuid, 'name': name});

  Future<void> deleteDatabase(String serverUuid, String databaseUuid) =>
      _request('DELETE',
          '/api/client/servers/$serverUuid/databases/$databaseUuid');

  Future<String?> rotateDatabasePassword(
      String serverUuid, String databaseUuid) async {
    final json = await _request(
        'POST',
        '/api/client/servers/$serverUuid/databases/$databaseUuid/rotate-password');
    return json['password'] as String?;
  }

  Future<int> getDatabaseSize(
      String serverUuid, String databaseUuid) async {
    final json = await _request('GET',
        '/api/client/servers/$serverUuid/databases/$databaseUuid/size');
    return (json['size'] as num? ?? 0).toInt();
  }

  // ──────────────────────── Schedules ────────────────────────

  Future<Paginated<Schedule>> getSchedules(String serverUuid,
      {int page = 1, int perPage = 25}) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/schedules',
        query: pageQuery(page, perPage));
    return Paginated.fromJson(
        json['schedules'] as Map<String, dynamic>, Schedule.fromJson);
  }

  Future<void> createSchedule(String serverUuid, Map<String, dynamic> body) =>
      _request('POST', '/api/client/servers/$serverUuid/schedules',
          body: body);

  Future<void> updateSchedule(String serverUuid, String scheduleUuid,
          Map<String, dynamic> body) =>
      _request('PATCH',
          '/api/client/servers/$serverUuid/schedules/$scheduleUuid',
          body: body);

  Future<void> deleteSchedule(String serverUuid, String scheduleUuid) =>
      _request('DELETE',
          '/api/client/servers/$serverUuid/schedules/$scheduleUuid');

  Future<void> triggerSchedule(String serverUuid, String scheduleUuid) =>
      _request('POST',
          '/api/client/servers/$serverUuid/schedules/$scheduleUuid/trigger',
          body: {'skip_condition': true});

  Future<void> abortSchedule(String serverUuid, String scheduleUuid) =>
      _request('POST',
          '/api/client/servers/$serverUuid/schedules/$scheduleUuid/abort');

  Future<Map<String, dynamic>> getScheduleStatus(
      String serverUuid, String scheduleUuid) async {
    final json = await _request('GET',
        '/api/client/servers/$serverUuid/schedules/$scheduleUuid/status');
    return json['status'] as Map<String, dynamic>? ?? const {};
  }

  Future<List<ScheduleStep>> getScheduleSteps(
      String serverUuid, String scheduleUuid) async {
    final json = await _request('GET',
        '/api/client/servers/$serverUuid/schedules/$scheduleUuid/steps');
    return (json['schedule_steps'] as List? ?? const [])
        .map((e) => ScheduleStep.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createScheduleStep(String serverUuid, String scheduleUuid,
          Map<String, dynamic> action) =>
      _request('POST',
          '/api/client/servers/$serverUuid/schedules/$scheduleUuid/steps',
          body: {'action': action});

  Future<void> updateScheduleStep(String serverUuid, String scheduleUuid,
          String stepUuid, Map<String, dynamic> action) =>
      _request(
          'PATCH',
          '/api/client/servers/$serverUuid/schedules/$scheduleUuid/steps/$stepUuid',
          body: {'action': action});

  Future<void> deleteScheduleStep(
          String serverUuid, String scheduleUuid, String stepUuid) =>
      _request('DELETE',
          '/api/client/servers/$serverUuid/schedules/$scheduleUuid/steps/$stepUuid');

  Future<Map<String, dynamic>> exportSchedule(
          String serverUuid, String scheduleUuid) =>
      _request('GET',
          '/api/client/servers/$serverUuid/schedules/$scheduleUuid/export');

  Future<void> importSchedule(
          String serverUuid, Map<String, dynamic> data) =>
      _request('POST', '/api/client/servers/$serverUuid/schedules/import',
          body: data);

  // ──────────────────────── Subusers ────────────────────────

  Future<Paginated<Subuser>> getSubusers(String serverUuid,
      {int page = 1, int perPage = 25}) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/subusers',
        query: pageQuery(page, perPage));
    return Paginated.fromJson(
        json['subusers'] as Map<String, dynamic>, Subuser.fromJson);
  }

  Future<void> createSubuser(
          String serverUuid, String email, List<String> permissions) =>
      _request('POST', '/api/client/servers/$serverUuid/subusers', body: {
        'email': email,
        'permissions': permissions,
        'ignored_files': <String>[],
      });

  Future<void> updateSubuser(
          String serverUuid, String userUuid, List<String> permissions) =>
      _request(
          'PATCH', '/api/client/servers/$serverUuid/subusers/$userUuid',
          body: {'permissions': permissions});

  Future<void> deleteSubuser(String serverUuid, String userUuid) =>
      _request(
          'DELETE', '/api/client/servers/$serverUuid/subusers/$userUuid');

  // ─────────────────────── Allocations ───────────────────────

  Future<Paginated<ServerAllocation>> getAllocations(String serverUuid,
      {int page = 1, int perPage = 50}) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/allocations',
        query: pageQuery(page, perPage));
    return Paginated.fromJson(json['allocations'] as Map<String, dynamic>,
        ServerAllocation.fromJson);
  }

  Future<void> createAllocation(String serverUuid) =>
      _request('POST', '/api/client/servers/$serverUuid/allocations');

  Future<void> updateAllocation(
          String serverUuid, String allocationUuid,
          {String? notes, bool? primary}) =>
      _request('PATCH',
          '/api/client/servers/$serverUuid/allocations/$allocationUuid',
          body: {
            if (notes != null) 'notes': notes,
            if (primary != null) 'primary': primary,
          });

  Future<void> deleteAllocation(
          String serverUuid, String allocationUuid) =>
      _request('DELETE',
          '/api/client/servers/$serverUuid/allocations/$allocationUuid');

  // ───────────────────────── Startup ─────────────────────────

  Future<List<StartupVariable>> getStartupVariables(
      String serverUuid) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/startup/variables');
    return (json['variables'] as List? ?? const [])
        .map((e) => StartupVariable.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateStartupVariable(
          String serverUuid, String envVariable, String value) =>
      _request('PUT', '/api/client/servers/$serverUuid/startup/variables',
          body: {
            'variables': [
              {'env_variable': envVariable, 'value': value}
            ],
          });

  Future<void> updateStartupCommand(String serverUuid, String command) =>
      _request('PUT', '/api/client/servers/$serverUuid/startup/command',
          body: {'command': command});

  Future<void> updateDockerImage(String serverUuid, String image) =>
      _request(
          'PUT', '/api/client/servers/$serverUuid/startup/docker-image',
          body: {'image': image});

  // ──────────────────────── Settings ────────────────────────

  Future<void> renameServer(String serverUuid,
          {String? name, String? description}) =>
      _request('POST', '/api/client/servers/$serverUuid/settings/rename',
          body: {'name': name, 'description': description});

  Future<void> updateTimezone(String serverUuid, String? timezone) =>
      _request('PUT', '/api/client/servers/$serverUuid/settings/timezone',
          body: {'timezone': timezone});

  Future<void> updateAutoKill(
          String serverUuid, bool enabled, int seconds) =>
      _request('PUT', '/api/client/servers/$serverUuid/settings/auto-kill',
          body: {'enabled': enabled, 'seconds': seconds});

  Future<void> updateAutoStart(String serverUuid, String behavior) =>
      _request(
          'PUT', '/api/client/servers/$serverUuid/settings/auto-start',
          body: {'behavior': behavior});

  Future<void> reinstallServer(String serverUuid,
          {bool truncateDirectory = false}) =>
      _request('POST', '/api/client/servers/$serverUuid/settings/install',
          body: {'truncate_directory': truncateDirectory});

  Future<void> cancelInstall(String serverUuid) => _request(
      'POST', '/api/client/servers/$serverUuid/settings/install/cancel');

  // ───────────────────────── Mounts ─────────────────────────

  Future<Paginated<ServerMount>> getMounts(String serverUuid,
      {int page = 1, int perPage = 50}) async {
    final json = await _request(
        'GET', '/api/client/servers/$serverUuid/mounts',
        query: pageQuery(page, perPage));
    return Paginated.fromJson(
        json['mounts'] as Map<String, dynamic>, ServerMount.fromJson);
  }

  Future<void> attachMount(String serverUuid, String mountUuid) =>
      _request('POST', '/api/client/servers/$serverUuid/mounts',
          body: {'mount_uuid': mountUuid});

  Future<void> detachMount(String serverUuid, String mountUuid) =>
      _request(
          'DELETE', '/api/client/servers/$serverUuid/mounts/$mountUuid');
}
