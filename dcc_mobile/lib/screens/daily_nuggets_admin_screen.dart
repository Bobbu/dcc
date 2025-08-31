import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';

class DailyNuggetsAdminScreen extends StatefulWidget {
  const DailyNuggetsAdminScreen({super.key});

  @override
  State<DailyNuggetsAdminScreen> createState() => _DailyNuggetsAdminScreenState();
}

class _DailyNuggetsAdminScreenState extends State<DailyNuggetsAdminScreen> {
  List<Map<String, dynamic>> _subscribers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedTimezone = 'All';
  bool _showActiveOnly = true;
  
  final List<String> _timezoneFilters = [
    'All',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'Europe/London',
    'Asia/Tokyo',
    'Australia/Sydney',
  ];

  @override
  void initState() {
    super.initState();
    _loadSubscribers();
  }

  Future<void> _loadSubscribers() async {
    try {
      setState(() => _isLoading = true);
      
      final token = await AuthService.getIdToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final apiUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
      final response = await http.get(
        Uri.parse('$apiUrl/admin/subscriptions'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _subscribers = List<Map<String, dynamic>>.from(data['subscribers'] ?? []);
          _isLoading = false;
        });
        LoggerService.info('Loaded ${_subscribers.length} subscribers');
      } else if (response.statusCode == 404) {
        setState(() {
          _subscribers = [];
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load subscribers: ${response.body}');
      }
    } catch (e) {
      LoggerService.error('Error loading subscribers: $e');
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading subscribers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredSubscribers {
    return _subscribers.where((subscriber) {
      // Filter by active status
      if (_showActiveOnly && !(subscriber['is_subscribed'] ?? false)) {
        return false;
      }
      
      // Filter by timezone
      if (_selectedTimezone != 'All' && 
          subscriber['timezone'] != _selectedTimezone) {
        return false;
      }
      
      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final email = (subscriber['email'] ?? '').toLowerCase();
        return email.contains(_searchQuery.toLowerCase());
      }
      
      return true;
    }).toList();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMM d, y h:mm a').format(date.toLocal());
    } catch (e) {
      return dateStr;
    }
  }

  String _getTimezoneDisplay(String? timezone) {
    if (timezone == null) return 'Not set';
    final parts = timezone.split('/');
    if (parts.length > 1) {
      return parts.last.replaceAll('_', ' ');
    }
    return timezone;
  }

  Widget _buildStatsCard() {
    final totalSubscribers = _subscribers.length;
    final activeSubscribers = _subscribers.where((s) => s['is_subscribed'] == true).length;
    final inactiveSubscribers = totalSubscribers - activeSubscribers;
    
    // Group by timezone for active subscribers
    final timezoneGroups = <String, int>{};
    for (final subscriber in _subscribers) {
      if (subscriber['is_subscribed'] == true) {
        final timezone = subscriber['timezone'] ?? 'Unknown';
        timezoneGroups[timezone] = (timezoneGroups[timezone] ?? 0) + 1;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Subscription Statistics',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Total', totalSubscribers, Icons.people),
                _buildStatItem('Active', activeSubscribers, Icons.check_circle, Colors.green),
                _buildStatItem('Inactive', inactiveSubscribers, Icons.cancel, Colors.orange),
              ],
            ),
            if (timezoneGroups.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Active Subscribers by Timezone',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...timezoneGroups.entries.map((entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        _getTimezoneDisplay(entry.key),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${entry.value} ${entry.value == 1 ? 'subscriber' : 'subscribers'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int value, IconData icon, [Color? color]) {
    return Column(
      children: [
        Icon(
          icon,
          size: 32,
          color: color ?? Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color ?? Theme.of(context).colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Nuggets Subscribers'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSubscribers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsCard(),
                  const SizedBox(height: 16),
                  
                  // Filters Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.filter_list,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Filters',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // Search field
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Search by email',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          
                          // Filter controls row
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _selectedTimezone,
                                  decoration: InputDecoration(
                                    labelText: 'Timezone',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  items: _timezoneFilters.map((timezone) {
                                    return DropdownMenuItem(
                                      value: timezone,
                                      child: Text(_getTimezoneDisplay(timezone)),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedTimezone = value;
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilterChip(
                                label: const Text('Active Only'),
                                selected: _showActiveOnly,
                                onSelected: (selected) {
                                  setState(() {
                                    _showActiveOnly = selected;
                                  });
                                },
                                selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Subscribers List
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.people_outline,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Subscribers (${_filteredSubscribers.length})',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          if (_filteredSubscribers.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.inbox,
                                      size: 64,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No subscribers found',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _filteredSubscribers.length,
                              separatorBuilder: (context, index) => const Divider(),
                              itemBuilder: (context, index) {
                                final subscriber = _filteredSubscribers[index];
                                final isActive = subscriber['is_subscribed'] ?? false;
                                
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isActive 
                                      ? Colors.green.withOpacity(0.2)
                                      : Colors.orange.withOpacity(0.2),
                                    child: Icon(
                                      isActive ? Icons.check_circle : Icons.pause_circle,
                                      color: isActive ? Colors.green : Colors.orange,
                                    ),
                                  ),
                                  title: Text(
                                    subscriber['email'] ?? 'Unknown',
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 14,
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Timezone: ${_getTimezoneDisplay(subscriber['timezone'])}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today,
                                            size: 14,
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Subscribed: ${_formatDate(subscriber['created_at'])}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                      if (subscriber['delivery_method'] != null) ...[
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(
                                              subscriber['delivery_method'] == 'email' 
                                                ? Icons.email 
                                                : Icons.notifications,
                                              size: 14,
                                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Method: ${subscriber['delivery_method']}',
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isActive)
                                        Chip(
                                          label: const Text('Inactive'),
                                          backgroundColor: Colors.orange.withOpacity(0.2),
                                          labelStyle: const TextStyle(
                                            color: Colors.orange,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}