import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NetworkRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // --- Connections ---

  /// Sends a connection request to the target user.
  /// Returns the ID of the new connection.
  Future<String> sendConnectionRequest(String targetUserId) async {
    try {
      final response = await _client.rpc(
        'send_connection_request',
        params: {'target_user_id': targetUserId},
      );
      return response as String;
    } catch (e) {
      throw Exception('Failed to send connection request: $e');
    }
  }

  /// Fetches the user's accepted connections.
  Future<List<Map<String, dynamic>>> getMyConnections() async {
    try {
      final response = await _client.rpc('get_my_connections');
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      throw Exception('Failed to fetch connections: $e');
    }
  }

  /// Fetches pending connection requests received by the user.
  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    try {
      final response = await _client.rpc('get_pending_requests');
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      throw Exception('Failed to fetch pending requests: $e');
    }
  }

  /// Accepts a connection request.
  Future<void> acceptConnectionRequest(String connectionId) async {
    try {
      await _client
          .from('connections')
          .update({'status': 'accepted'})
          .eq('id', connectionId);
    } catch (e) {
      throw Exception('Failed to accept request: $e');
    }
  }

  /// Rejects or Ignores a connection request.
  Future<void> ignoreConnectionRequest(String connectionId) async {
    try {
      await _client
          .from('connections')
          .update({'status': 'rejected'})
          .eq('id', connectionId);
    } catch (e) {
      throw Exception('Failed to ignore request: $e');
    }
  }

  /// Checks the connection status between the current user and a target user.
  /// Returns: 'pending', 'accepted', 'rejected', 'blocked', or null (if no connection).
  Future<String?> getConnectionStatus(String targetUserId) async {
    try {
      final response = await _client.rpc(
        'get_connection_status',
        params: {'target_user_id': targetUserId},
      );
      return response as String?;
    } catch (e) {
      // It might return null if no connection exists
      return null;
    }
  }

  // --- Search ---

  /// Searches for profiles by name or email (excluding current user).
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      debugPrint('🔍 Searching for: $query');
      final response = await _client.rpc(
        'search_profiles',
        params: {'search_query': query},
      );
      debugPrint('🔍 Search response type: ${response.runtimeType}');
      debugPrint('🔍 Search response: $response');
      final results = List<Map<String, dynamic>>.from(response as List);
      debugPrint('🔍 Found ${results.length} results');
      return results;
    } catch (e) {
      debugPrint('❌ Search error: $e');
      throw Exception('Failed to search users: $e');
    }
  }

  // --- Messages ---

  /// Fetches the list of conversations (users you've messaged with).
  Future<List<Map<String, dynamic>>> getMyConversations() async {
    try {
      final response = await _client.rpc('get_my_conversations');
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      throw Exception('Failed to fetch conversations: $e');
    }
  }

  /// Clears chat history with a specific user.
  Future<void> clearChatHistory(String targetUserId) async {
    try {
      await _client.rpc(
        'clear_chat_history',
        params: {'target_user_id': targetUserId},
      );
    } catch (e) {
      throw Exception('Failed to clear chat: $e');
    }
  }

  /// Fetches suggested connections (2nd-degree connections).
  Future<List<Map<String, dynamic>>> getSuggestedConnections() async {
    try {
      final response = await _client.rpc('get_suggested_connections');
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error getting suggested connections: $e');
      // Return empty list instead of throwing to prevent UI break
      return [];
    }
  }

  // (Messaging methods will be added later)
}
