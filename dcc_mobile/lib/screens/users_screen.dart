import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/auth_service.dart';
import 'dart:io' show Platform;

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String _filterGroup = 'all';
  String _sortBy = 'created_at';
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
      final jwtToken = await AuthService.getIdToken();

      if (jwtToken == null) {
        setState(() {
          _error = 'No authentication token found';
          _isLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('$baseUrl/admin/users'),
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _users = List<Map<String, dynamic>>.from(data['users']);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load users: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading users: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    var filtered = _users.where((user) {
      final searchLower = _searchQuery.toLowerCase();
      final email = (user['email'] ?? '').toString().toLowerCase();
      final name = (user['display_name'] ?? '').toString().toLowerCase();
      final username = (user['username'] ?? '').toString().toLowerCase();
      
      final matchesSearch = searchLower.isEmpty ||
          email.contains(searchLower) ||
          name.contains(searchLower) ||
          username.contains(searchLower);
      
      final matchesFilter = _filterGroup == 'all' ||
          (_filterGroup == 'admins' && user['is_admin'] == true) ||
          (_filterGroup == 'users' && user['is_admin'] != true) ||
          (_filterGroup == 'subscribed' && user['daily_nuggets_subscribed'] == true) ||
          (_filterGroup == 'unverified' && user['email_verified'] != true);
      
      return matchesSearch && matchesFilter;
    }).toList();

    filtered.sort((a, b) {
      dynamic aValue, bValue;
      
      switch (_sortBy) {
        case 'email':
          aValue = a['email'] ?? '';
          bValue = b['email'] ?? '';
          break;
        case 'display_name':
          aValue = a['display_name'] ?? a['email'] ?? '';
          bValue = b['display_name'] ?? b['email'] ?? '';
          break;
        case 'status':
          aValue = a['status'] ?? '';
          bValue = b['status'] ?? '';
          break;
        case 'daily_nuggets':
          aValue = a['daily_nuggets_subscribed'] == true ? 1 : 0;
          bValue = b['daily_nuggets_subscribed'] == true ? 1 : 0;
          break;
        case 'created_at':
        default:
          aValue = a['created_at'] ?? '';
          bValue = b['created_at'] ?? '';
          break;
      }

      if (aValue is String && bValue is String) {
        return _sortAscending 
            ? aValue.compareTo(bValue)
            : bValue.compareTo(aValue);
      } else if (aValue is num && bValue is num) {
        return _sortAscending
            ? aValue.compareTo(bValue)
            : bValue.compareTo(aValue);
      }
      return 0;
    });

    return filtered;
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '-';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM d, y h:mm a').format(date);
    } catch (e) {
      return dateString;
    }
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final bool isApple = Platform.isIOS || Platform.isMacOS;
    final email = user['email'] ?? 'No email';
    final displayName = user['display_name'] ?? user['username'] ?? '';
    final isAdmin = user['is_admin'] == true;
    final isSubscribed = user['daily_nuggets_subscribed'] == true;
    final isVerified = user['email_verified'] == true;
    final status = user['status'] ?? '';
    final createdAt = _formatDate(user['created_at']);
    final groups = (user['groups'] as List?)?.join(', ') ?? '';
    
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: isAdmin 
              ? Colors.orange.withValues(alpha: 0.2)
              : Theme.of(context).primaryColor.withValues(alpha: 0.2),
          child: Icon(
            isApple ? CupertinoIcons.person_fill : Icons.person,
            color: isAdmin 
                ? Colors.orange
                : Theme.of(context).primaryColor,
          ),
        ),
        title: Text(
          displayName.isNotEmpty ? displayName : email,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (displayName.isNotEmpty) Text(email),
            Row(
              children: [
                if (isAdmin) 
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(right: 4, top: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Admin',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (isSubscribed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(right: 4, top: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Daily Nuggets',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (!isVerified)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Unverified',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('User ID', user['user_id'] ?? '-'),
                _buildDetailRow('Username', user['username'] ?? '-'),
                _buildDetailRow('Status', status),
                _buildDetailRow('Email Verified', isVerified ? 'Yes' : 'No'),
                _buildDetailRow('Groups', groups.isNotEmpty ? groups : 'Users'),
                _buildDetailRow('Created', createdAt),
                _buildDetailRow('Last Modified', _formatDate(user['last_modified'])),
                if (isSubscribed) ...[
                  const Divider(),
                  const Text(
                    'Daily Nuggets Subscription',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow('Timezone', user['timezone'] ?? '-'),
                  _buildDetailRow('Preferred Time', user['preferred_time'] ?? '-'),
                  _buildDetailRow('Subscribed On', _formatDate(user['subscription_created_at'])),
                  _buildDetailRow('Last Updated', _formatDate(user['subscription_updated_at'])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isApple = Platform.isIOS || Platform.isMacOS;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          IconButton(
            icon: Icon(isApple ? CupertinoIcons.refresh : Icons.refresh),
            onPressed: _loadUsers,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by email, name, or username',
                    prefixIcon: Icon(
                      isApple ? CupertinoIcons.search : Icons.search,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _filterGroup,
                        decoration: InputDecoration(
                          labelText: 'Filter',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).cardColor,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All Users')),
                          DropdownMenuItem(value: 'admins', child: Text('Admins')),
                          DropdownMenuItem(value: 'users', child: Text('Regular Users')),
                          DropdownMenuItem(value: 'subscribed', child: Text('Daily Nuggets')),
                          DropdownMenuItem(value: 'unverified', child: Text('Unverified')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _filterGroup = value ?? 'all';
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _sortBy,
                        decoration: InputDecoration(
                          labelText: 'Sort By',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).cardColor,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'created_at', child: Text('Created Date')),
                          DropdownMenuItem(value: 'email', child: Text('Email')),
                          DropdownMenuItem(value: 'display_name', child: Text('Name')),
                          DropdownMenuItem(value: 'status', child: Text('Status')),
                          DropdownMenuItem(value: 'daily_nuggets', child: Text('Subscription')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _sortBy = value ?? 'created_at';
                          });
                        },
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _sortAscending
                            ? (isApple ? CupertinoIcons.arrow_up : Icons.arrow_upward)
                            : (isApple ? CupertinoIcons.arrow_down : Icons.arrow_downward),
                      ),
                      onPressed: () {
                        setState(() {
                          _sortAscending = !_sortAscending;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Total: ${_filteredUsers.length} users',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isApple ? CupertinoIcons.exclamationmark_triangle : Icons.error_outline,
                              size: 48,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadUsers,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _filteredUsers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isApple ? CupertinoIcons.person_3 : Icons.people_outline,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No users found',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadUsers,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16.0),
                              itemCount: _filteredUsers.length,
                              itemBuilder: (context, index) {
                                return _buildUserTile(_filteredUsers[index]);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}