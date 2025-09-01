import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';
import '../services/daily_nuggets_service.dart';
import '../themes.dart';
import 'login_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  bool _isLoading = true;
  bool _isSaving = false;
  String? _userEmail;
  String? _userName;
  
  // Subscription settings
  bool _subscribeToDailyNuggets = false;
  String _deliveryMethod = 'email'; // 'email' or 'notifications'
  String _selectedTimezone = 'America/New_York'; // Default timezone
  List<String> _timezones = []; // List of available timezones
  
  @override
  void initState() {
    super.initState();
    _checkAuthenticationAndLoad();
  }

  Future<void> _checkAuthenticationAndLoad() async {
    try {
      // Check if user is authenticated
      final isSignedIn = await AuthService.isSignedIn();
      
      if (!isSignedIn) {
        // User not signed in - redirect to login
        LoggerService.info('🔒 User not authenticated, redirecting to login');
        if (mounted) {
          // Navigate to login with instruction to return to profile after login
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const LoginScreen(
                redirectToProfileAfterLogin: true,
              ),
            ),
          );
        }
        return;
      }

      // User is authenticated - load profile data
      _loadUserProfile();
      _loadTimezones();
    } catch (e) {
      LoggerService.error('🔒 Error checking authentication: $e');
      // On error, redirect to login for safety
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginScreen(
              redirectToProfileAfterLogin: true,
            ),
          ),
        );
      }
    }
  }
  
  Future<void> _loadTimezones() async {
    try {
      // Get the device's current timezone
      final String deviceTimezone = await FlutterTimezone.getLocalTimezone();
      
      // Define major timezones for selection
      final majorTimezones = [
        'America/New_York',
        'America/Chicago',
        'America/Denver',
        'America/Los_Angeles',
        'America/Phoenix',
        'America/Anchorage',
        'Pacific/Honolulu',
        'Europe/London',
        'Europe/Paris',
        'Europe/Berlin',
        'Asia/Tokyo',
        'Asia/Shanghai',
        'Asia/Kolkata',
        'Australia/Sydney',
        'Australia/Melbourne',
        'America/Toronto',
        'America/Mexico_City',
        'America/Sao_Paulo',
        'Africa/Cairo',
        'Asia/Dubai',
      ];
      
      setState(() {
        _timezones = majorTimezones;
        // Use device timezone if it's in our list, otherwise default to New York
        if (majorTimezones.contains(deviceTimezone)) {
          _selectedTimezone = deviceTimezone;
        }
      });
      
      LoggerService.info('Device timezone detected: $deviceTimezone');
    } catch (e) {
      LoggerService.error('Error loading timezones: $e', error: e);
      // Fallback to basic timezones
      setState(() {
        _timezones = ['America/New_York', 'America/Chicago', 'America/Los_Angeles', 'Europe/London'];
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      setState(() => _isLoading = true);
      
      // Load user data from Cognito
      final email = await AuthService.getUserEmail();
      final name = await AuthService.getUserName();
      
      // Load subscription preferences from backend only (no local storage)
      bool subscribeToDailyNuggets = false;
      String deliveryMethod = 'email';
      String timezone = _selectedTimezone;
      
      try {
        // Get subscription from backend - single source of truth
        final subscription = await DailyNuggetsService.getSubscription();
        if (subscription != null) {
          subscribeToDailyNuggets = subscription.isSubscribed;
          // Force email delivery method until push notifications are implemented
          deliveryMethod = subscription.deliveryMethod == 'notifications' ? 'email' : subscription.deliveryMethod;
          timezone = subscription.timezone;
          LoggerService.info('📧 Loaded subscription from backend: subscribed=$subscribeToDailyNuggets');
        } else {
          LoggerService.info('📧 No backend subscription found - user not subscribed');
          // User has no subscription - use defaults
          subscribeToDailyNuggets = false;
          deliveryMethod = 'email';
          timezone = _selectedTimezone;
        }
      } catch (e) {
        LoggerService.error('📧 Error loading backend subscription: $e');
        // If backend fails, use defaults (no fallback to local storage)
        subscribeToDailyNuggets = false;
        deliveryMethod = 'email';
        timezone = _selectedTimezone;
      }
      
      setState(() {
        _userEmail = email;
        _userName = name;
        _nameController.text = name ?? '';
        _subscribeToDailyNuggets = subscribeToDailyNuggets;
        _deliveryMethod = deliveryMethod;
        _selectedTimezone = timezone;
        _isLoading = false;
      });
      
      LoggerService.info('✅ User profile loaded successfully for $email');
    } catch (e) {
      LoggerService.error('❌ Error loading user profile: $e', error: e);
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    try {
      setState(() => _isSaving = true);
      
      // Update the user's name in Cognito
      final newName = _nameController.text.trim();
      if (newName != _userName) {
        await AuthService.updateUserName(newName);
      }
      
      // Save subscription preferences to backend only (single source of truth)
      try {
        await DailyNuggetsService.updateSubscription(
          isSubscribed: _subscribeToDailyNuggets,
          deliveryMethod: _deliveryMethod,
          timezone: _selectedTimezone,
        );
        LoggerService.info('📧 Subscription saved to backend successfully');
      } catch (e) {
        LoggerService.error('📧 Error saving subscription to backend: $e');
        // Re-throw error to show user that save failed
        throw Exception('Failed to save subscription preferences: $e');
      }
      
      LoggerService.info('✅ Profile saved successfully');
      LoggerService.info('   Name: ${_nameController.text.trim()}');
      LoggerService.info('   Subscribe to Daily Nuggets: $_subscribeToDailyNuggets');
      LoggerService.info('   Delivery Method: $_deliveryMethod');
      LoggerService.info('   Timezone: $_selectedTimezone');
      
      // Update local state
      setState(() {
        _userName = newName;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _subscribeToDailyNuggets 
                ? 'Profile saved! You\'ll receive daily quotes at 8:00 AM ${_selectedTimezone.split('/').last.replaceAll('_', ' ')} time.'
                : 'Profile saved successfully!',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
        
        // Return true to indicate the profile was updated
        Navigator.pop(context, true);
      }
    } catch (e) {
      LoggerService.error('❌ Error saving profile: $e', error: e);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _sendTestEmail() async {
    try {
      await DailyNuggetsService.sendTestEmail();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test email sent! Check your inbox in a few moments.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      LoggerService.error('❌ Error sending test email: $e', error: e);
      
      String errorMessage = 'Failed to send test email';
      Color errorColor = Colors.red;
      
      // Handle specific token exceptions more gracefully
      if (e.toString().contains('expired') || e.toString().contains('session')) {
        errorMessage = 'Your session has expired. Please sign out and sign in again to continue.';
        errorColor = Colors.orange;
      } else if (e.toString().contains('authentication') || e.toString().contains('sign in')) {
        errorMessage = e.toString();
        errorColor = Colors.orange;
      } else {
        errorMessage = 'Failed to send test email: $e';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: errorColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        actions: [],
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
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Information Section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Profile Information',
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            // Email field (read-only)
                            TextFormField(
                              initialValue: _userEmail ?? '',
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email),
                                enabled: false,
                              ),
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Name field (editable)
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Display Name',
                                prefixIcon: Icon(Icons.badge),
                                hintText: 'Enter your preferred name',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your display name';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Daily Nuggets Subscription Section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Daily Nuggets',
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Get inspired daily with carefully selected quotes delivered to you.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            
                            // Subscribe toggle
                            SwitchListTile(
                              title: Text(
                                'Receive Daily Nuggets',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              subtitle: Text(
                                _subscribeToDailyNuggets 
                                  ? 'You\'ll receive one inspiring quote daily'
                                  : 'Enable to receive daily inspirational quotes',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              value: _subscribeToDailyNuggets,
                              onChanged: (value) {
                                setState(() {
                                  _subscribeToDailyNuggets = value;
                                });
                              },
                              activeColor: Theme.of(context).colorScheme.primary,
                              contentPadding: EdgeInsets.zero,
                            ),
                            
                            // Delivery method selection (only show if subscribed)
                            if (_subscribeToDailyNuggets) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Delivery Method',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              
                              // Email option
                              RadioListTile<String>(
                                title: Row(
                                  children: [
                                    Icon(
                                      Icons.email,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Email',
                                      style: Theme.of(context).textTheme.bodyLarge,
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  'Receive quotes in your inbox daily',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                value: 'email',
                                groupValue: _deliveryMethod,
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _deliveryMethod = value;
                                    });
                                  }
                                },
                                activeColor: Theme.of(context).colorScheme.primary,
                                contentPadding: const EdgeInsets.only(left: 8),
                              ),
                              
                              // Notifications option (disabled for now)
                              RadioListTile<String>(
                                title: Row(
                                  children: [
                                    Icon(
                                      Icons.notifications,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Push Notifications',
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.secondary.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Coming Soon',
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: Theme.of(context).colorScheme.secondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  'Get notified directly on your device',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                                  ),
                                ),
                                value: 'notifications',
                                groupValue: _deliveryMethod,
                                onChanged: null, // Disabled
                                activeColor: Theme.of(context).colorScheme.primary,
                                contentPadding: const EdgeInsets.only(left: 8),
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Timezone selection
                              Text(
                                'Delivery Time',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: _selectedTimezone,
                                decoration: InputDecoration(
                                  labelText: 'Your Timezone',
                                  prefixIcon: Icon(Icons.access_time),
                                  helperText: 'Quotes will be delivered at 8:00 AM in your selected timezone',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                items: _timezones.map((String timezone) {
                                  // Format timezone display name
                                  final parts = timezone.split('/');
                                  final city = parts.last.replaceAll('_', ' ');
                                  final region = parts.first;
                                  
                                  return DropdownMenuItem<String>(
                                    value: timezone,
                                    child: Text('$city ($region)'),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      _selectedTimezone = newValue;
                                    });
                                  }
                                },
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Test Email Button
                              if (_subscribeToDailyNuggets && _deliveryMethod == 'email') ...[
                                Center(
                                  child: OutlinedButton.icon(
                                    onPressed: _sendTestEmail,
                                    icon: const Icon(Icons.email_outlined),
                                    label: const Text('Send Test Email'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Theme.of(context).colorScheme.secondary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Daily nuggets will be delivered every morning at 8:00 AM in your local timezone.',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.secondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Save button (alternative to app bar save)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveProfile,
                        icon: _isSaving 
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                            )
                          : const Icon(Icons.save),
                        label: Text(
                          _isSaving ? 'Saving...' : 'Save Profile',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}