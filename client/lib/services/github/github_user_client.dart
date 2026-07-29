import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_http.dart';

/// Reads the authenticated GitHub account for a personal access / device token.
class GithubUserClient {
  GithubUserClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Returns the `login` of the account owning [token].
  Future<String> fetchLogin({required String token}) async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/user'),
      headers: githubApiHeaders(token: token),
    );
    if (response.statusCode != 200) {
      throw StateError(
        'GitHub user lookup failed (${response.statusCode}): ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final login = (body['login'] as String?)?.trim() ?? '';
    if (login.isEmpty) {
      throw StateError('GitHub user lookup returned no login');
    }
    return login;
  }
}
