import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/auth_service.dart';

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
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadUsers();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final userId = await AuthService.getCurrentUserId();
      setState(() {
        _currentUserId = userId;
      });
    } catch (e) {
      // Handle error silently
    }
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
          (_filterGroup == 'unverified' && user['email_verified'] != true && user['status'] != 'EXTERNAL_PROVIDER') ||
          (_filterGroup == 'federated' && user['status'] == 'EXTERNAL_PROVIDER');
      
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

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final userId = user['user_id'];
    final userEmail = user['email'] ?? 'Unknown';
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete User'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to permanently delete this user?'),
            const SizedBox(height: 8),
            Text('Email: $userEmail', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text(
              'This action cannot be undone. All user data will be permanently removed.',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Deleting user...'),
          ],
        ),
      ),
    );
    
    try {
      final baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
      final jwtToken = await AuthService.getIdToken();
      
      if (jwtToken == null) {
        throw Exception('No authentication token found');
      }
      
      final response = await http.delete(
        Uri.parse('$baseUrl/admin/users/$userId'),
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
      );
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
      if (response.statusCode == 200) {
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
        // Reload users to reflect changes
        _loadUsers();
      } else if (response.statusCode == 403) {
        final errorData = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorData['error'] ?? 'Operation not permitted'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else if (response.statusCode == 404) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        throw Exception('Failed to delete user: ${response.statusCode}');
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleAdminStatus(Map<String, dynamic> user) async {
    final userId = user['user_id'];
    final isAdmin = user['is_admin'] == true;
    final action = isAdmin ? 'remove' : 'add';
    final actionText = isAdmin ? 'Remove from' : 'Add to';
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$actionText Admins Group'),
        content: Text(
          isAdmin 
            ? 'Are you sure you want to remove ${user['email']} from the Admins group?'
            : 'Are you sure you want to add ${user['email']} to the Admins group?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isAdmin ? Colors.orange : Colors.green,
            ),
            child: Text(isAdmin ? 'Remove' : 'Add'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // Show loading indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Updating user...'),
          ],
        ),
      ),
    );
    
    try {
      final baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
      final jwtToken = await AuthService.getIdToken();
      
      if (jwtToken == null) {
        throw Exception('No authentication token found');
      }
      
      final response = await http.put(
        Uri.parse('$baseUrl/admin/users/$userId'),
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        body: json.encode({'action': action}),
      );
      
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();
      
      if (response.statusCode == 200) {
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isAdmin 
                  ? 'User removed from Admins group'
                  : 'User added to Admins group',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
        // Reload users to reflect changes
        _loadUsers();
      } else if (response.statusCode == 403) {
        final errorData = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorData['error'] ?? 'Operation not permitted'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        throw Exception('Failed to update user: ${response.statusCode}');
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final email = user['email'] ?? 'No email';
    final displayName = user['display_name'] ?? user['username'] ?? '';
    final isAdmin = user['is_admin'] == true;
    final isSubscribed = user['daily_nuggets_subscribed'] == true;
    final isVerified = user['email_verified'] == true;
    final status = user['status'] ?? '';
    final createdAt = _formatDate(user['created_at']);
    final groups = (user['groups'] as List?)?.join(', ') ?? '';
    
    // Check if user is federated (from external provider like Google)
    final isFederated = status == 'EXTERNAL_PROVIDER';
    
    return Card(
      child: ExpansionTile(
        trailing: user['user_id'] != _currentUserId
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isAdmin ? 'Admin' : 'User',
                  style: TextStyle(
                    fontSize: 12,
                    color: isAdmin ? Colors.orange : Colors.grey,
                  ),
                ),
                Switch(
                  value: isAdmin,
                  onChanged: (_) => _toggleAdminStatus(user),
                  activeTrackColor: Colors.orange.withValues(alpha: 0.5),
                  activeThumbColor: Colors.orange,
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () => _deleteUser(user),
                  tooltip: 'Delete user',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            )
          : null,
        leading: CircleAvatar(
          backgroundColor: isAdmin 
              ? Colors.orange.withValues(alpha: 0.2)
              : Theme.of(context).primaryColor.withValues(alpha: 0.2),
          child: Icon(
            kIsWeb ? Icons.person : CupertinoIcons.person_fill,
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
                // Show Federated badge for external providers, Unverified for regular unverified users
                if (!isVerified)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: isFederated ? Colors.blue : Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isFederated ? 'Federated' : 'Unverified',
                      style: const TextStyle(
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
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          IconButton(
            icon: Icon(kIsWeb ? Icons.refresh : CupertinoIcons.refresh),
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
                      kIsWeb ? Icons.search : CupertinoIcons.search,
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
                          DropdownMenuItem(value: 'federated', child: Text('Federated')),
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
                            ? (kIsWeb ? Icons.arrow_upward : CupertinoIcons.arrow_up)
                            : (kIsWeb ? Icons.arrow_downward : CupertinoIcons.arrow_down),
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
                              kIsWeb ? Icons.error_outline : CupertinoIcons.exclamationmark_triangle,
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
                                  kIsWeb ? Icons.people_outline : CupertinoIcons.person_3,
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