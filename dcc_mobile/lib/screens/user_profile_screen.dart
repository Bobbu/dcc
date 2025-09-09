import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';
import '../services/daily_nuggets_service.dart';
import '../services/fcm_service.dart';
import 'login_screen.dart';
import 'quote_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final bool fromDeepLink;
  
  const UserProfileScreen({
    super.key,
    this.fromDeepLink = false,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSendingTestEmail = false;
  bool _isSendingTestNotification = false;
  bool _isRequestingPushPermissions = false;
  bool _isFederatedUser = false;
  String? _userEmail;
  String? _userName;
  
  // Auto-save debounce timer for display name
  Timer? _nameDebounceTimer;
  bool _hasUnsavedChanges = false;
  String? _federatedProvider; // Track which provider (Google, Apple, etc.)
  
  // Subscription settings
  bool _subscribeToDailyNuggets = false;
  String _deliveryMethod = 'email'; // 'email' or 'notifications'
  String _selectedTimezone = 'America/New_York'; // Default timezone
  List<String> _timezones = []; // List of available timezones
  
  // Push notification settings
  bool _enablePushNotifications = false;
  bool _enableEmailNotifications = true;
  bool _pushPermissionsGranted = false;
  String _preferredTime = '08:00'; // HH:MM format

  // Helper function to convert 24-hour time to 12-hour format
  String _format12Hour(String time24) {
    final parts = time24.split(':');
    final hour24 = int.parse(parts[0]);
    final minute = parts[1];
    
    if (hour24 == 0) {
      return '12:$minute AM';
    } else if (hour24 < 12) {
      return '$hour24:$minute AM';
    } else if (hour24 == 12) {
      return '12:$minute PM';
    } else {
      return '${hour24 - 12}:$minute PM';
    }
  }
  List<String> _availableHours = [];
  
  @override
  void initState() {
    super.initState();
    _initializeAvailableHours();
    _checkAuthenticationAndLoad();
    
    // Add listener for name changes with debouncing
    _nameController.addListener(_onNameChanged);
    
    // Check push notification permissions on mobile
    if (!kIsWeb) {
      _checkPushPermissions();
    }
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
    _nameDebounceTimer?.cancel();
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _initializeAvailableHours() {
    _availableHours = List.generate(24, (index) {
      final hour = index.toString().padLeft(2, '0');
      return '$hour:00';
    });
  }

  Future<void> _checkPushPermissions() async {
    try {
      final fcmService = FCMService();
      if (fcmService.isInitialized) {
        final enabled = await fcmService.areNotificationsEnabled();
        setState(() {
          _pushPermissionsGranted = enabled;
        });
      }
    } catch (e) {
      LoggerService.error('Failed to check push permissions: $e');
    }
  }

  Future<void> _requestPushPermissions() async {
    setState(() {
      _isRequestingPushPermissions = true;
    });
    
    try {
      final fcmService = FCMService();
      
      LoggerService.info('🔔 User requesting push permissions...');
      LoggerService.info('🔔 FCM service instance created, calling requestPermissions...');
      LoggerService.info('🔔 FCM service initialized: ${fcmService.isInitialized}');
      
      // FCM should already be initialized in main.dart, just request permissions
      LoggerService.info('🔔 About to call fcmService.requestPermissions()...');
      await fcmService.requestPermissions();
      LoggerService.info('🔔 FCM requestPermissions call returned, checking permissions...');
      await _checkPushPermissions();
      
      if (_pushPermissionsGranted && mounted) {
        // Enable the push notification toggle
        setState(() {
          _enablePushNotifications = true;
        });
        _autoSaveProfile(showSnackbar: true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Push notifications enabled!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      LoggerService.error('Failed to request push permissions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to enable push notifications. Please check settings.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isRequestingPushPermissions = false;
      });
    }
  }

  String _getFormattedTime() {
    final hour24 = int.parse(_preferredTime.split(':')[0]);
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final period = hour24 < 12 ? 'AM' : 'PM';
    return '$hour12:00 $period';
  }

  Future<void> _loadUserProfile() async {
    try {
      setState(() => _isLoading = true);
      
      // Check if user is federated first and determine provider
      final groups = await AuthService.getUserGroups();
      final isFederatedUser = groups.any((group) => group.contains('Google') || group.contains('Apple') || group.contains('Facebook') || group.contains('SAML'));
      
      // Determine the specific federated provider
      String? federatedProvider;
      if (groups.any((group) => group.contains('Google'))) {
        federatedProvider = 'Google';
      } else if (groups.any((group) => group.contains('Apple'))) {
        federatedProvider = 'Apple';
      } else if (groups.any((group) => group.contains('Facebook'))) {
        federatedProvider = 'Facebook';
      } else if (groups.any((group) => group.contains('SAML'))) {
        federatedProvider = 'SAML';
      }
      
      // Load user data from Cognito
      final email = await AuthService.getUserEmail();
      final name = await AuthService.getUserName();
      
      // Load subscription preferences from backend only (no local storage)
      bool subscribeToDailyNuggets = false;
      String deliveryMethod = 'email';
      String timezone = _selectedTimezone;
      bool enableEmail = true;
      bool enablePush = false;
      String preferredTime = '08:00';
      
      try {
        // Get subscription from backend - single source of truth
        final subscription = await DailyNuggetsService.getSubscription();
        if (subscription != null) {
          subscribeToDailyNuggets = subscription.isSubscribed;
          deliveryMethod = subscription.deliveryMethod;
          timezone = subscription.timezone;
          
          // Load notification preferences if available
          final prefs = subscription.notificationPreferences;
          if (prefs != null) {
            enableEmail = prefs['enableEmail'] ?? true;
            enablePush = prefs['enablePush'] ?? false;
            preferredTime = prefs['preferredTime'] ?? '08:00';
          }
          
          LoggerService.info('📧 Loaded subscription from backend: subscribed=$subscribeToDailyNuggets, email=$enableEmail, push=$enablePush');
        } else {
          LoggerService.info('📧 No backend subscription found - user not subscribed');
          // User has no subscription - use defaults
          subscribeToDailyNuggets = false;
          deliveryMethod = 'email';
          timezone = _selectedTimezone;
          enableEmail = true;
          enablePush = false;
          preferredTime = '08:00';
        }
      } catch (e) {
        LoggerService.error('📧 Error loading backend subscription: $e');
        // If backend fails, use defaults (no fallback to local storage)
        subscribeToDailyNuggets = false;
        deliveryMethod = 'email';
        timezone = _selectedTimezone;
        enableEmail = true;
        enablePush = false;
        preferredTime = '08:00';
      }
      
      setState(() {
        _userEmail = email;
        _userName = name;
        // Set display name based on provider and available data
        if (!isFederatedUser && name != null) {
          _nameController.text = name; // Regular user with name
        } else if (federatedProvider == 'Apple' && (name == null || name.isEmpty)) {
          _nameController.text = 'Apple User'; // Apple user without name
        } else if (isFederatedUser && name != null) {
          _nameController.text = name; // Federated user with name
        } else {
          _nameController.text = ''; // Fallback
        }
        _isFederatedUser = isFederatedUser;
        _federatedProvider = federatedProvider;
        _subscribeToDailyNuggets = subscribeToDailyNuggets;
        _deliveryMethod = deliveryMethod;
        _selectedTimezone = timezone;
        _enableEmailNotifications = enableEmail;
        _enablePushNotifications = enablePush;
        _preferredTime = preferredTime;
        _isLoading = false;
      });
      
      LoggerService.info('✅ User profile loaded successfully for $email');
      
      // Reset unsaved changes flag after loading
      _hasUnsavedChanges = false;
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

  void _onNameChanged() {
    // Only debounce if user is not federated and the name has actually changed
    if (!_isFederatedUser && _nameController.text.trim() != _userName) {
      _hasUnsavedChanges = true;
      
      // Cancel existing timer
      _nameDebounceTimer?.cancel();
      
      // Start new timer
      _nameDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted && _hasUnsavedChanges) {
          _autoSaveProfile(showSnackbar: false);
        }
      });
    }
  }
  
  Future<void> _autoSaveProfile({bool showSnackbar = true}) async {
    // Skip if currently saving or loading
    if (_isSaving || _isLoading) return;
    
    // For auto-save, we'll silently save without full validation
    try {
      setState(() => _isSaving = true);
      
      // Update the user's name in Cognito (only for non-federated users)
      final newName = _nameController.text.trim();
      if (newName.isNotEmpty && newName != _userName && !_isFederatedUser) {
        await AuthService.updateUserName(newName);
        setState(() {
          _userName = newName;
        });
      }
      
      // Get current subscription to preserve FCM tokens
      final currentSub = await DailyNuggetsService.getSubscription();
      final existingPrefs = currentSub?.notificationPreferences ?? {};
      
      LoggerService.info('🔍 Current subscription before save: ${currentSub?.toJson()}');
      LoggerService.info('🔍 Existing notification preferences: $existingPrefs');
      LoggerService.info('🔍 FCM tokens in preferences: ${existingPrefs['fcmTokens']}');
      
      // Save subscription preferences to backend, preserving FCM tokens
      final newPreferences = {
        'enableEmail': _enableEmailNotifications,
        'enablePush': _enablePushNotifications,
        'preferredTime': _preferredTime,
        'timezone': _selectedTimezone,
        // Preserve any existing FCM tokens
        if (existingPrefs['fcmTokens'] != null) 'fcmTokens': existingPrefs['fcmTokens'],
      };
      
      LoggerService.info('🔍 New preferences being sent: $newPreferences');
      
      await DailyNuggetsService.updateSubscription(
        isSubscribed: _subscribeToDailyNuggets,
        deliveryMethod: _deliveryMethod,
        timezone: _selectedTimezone,
        notificationPreferences: newPreferences,
      );
      
      _hasUnsavedChanges = false;
      
      LoggerService.info('✅ Profile auto-saved successfully');
      
      if (showSnackbar && mounted) {
        final message = _subscribeToDailyNuggets 
          ? 'Changes saved! Daily quotes at ${_format12Hour(_preferredTime)} ${_selectedTimezone.split('/').last.replaceAll('_', ' ')} time.'
          : 'Changes saved!';
          
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // Handle deep link navigation after successful save
        _navigateAfterSave();
      }
    } catch (e) {
      LoggerService.error('❌ Error auto-saving profile: $e', error: e);
      // For auto-save, we don't show error messages to avoid annoying the user
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
  
  // Navigation helper for deep link scenarios
  void _navigateAfterSave() {
    if (!mounted) return;
    
    // Handle navigation based on how the user arrived at this screen
    if (widget.fromDeepLink) {
      // User came from deep link - navigate to main app
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const QuoteScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _sendTestEmail() async {
    setState(() {
      _isSendingTestEmail = true;
    });
    
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
    } finally {
      if (mounted) {
        setState(() {
          _isSendingTestEmail = false;
        });
      }
    }
  }

  Future<void> _sendTestNotification() async {
    setState(() {
      _isSendingTestNotification = true;
    });
    
    try {
      await DailyNuggetsService.sendTestNotification();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test notification sent! Check your device in a few moments.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      LoggerService.error('❌ Error sending test notification: $e', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send test notification: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingTestNotification = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Profile'),
            if (_hasUnsavedChanges && !_isSaving) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  'Unsaved',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ],
        ),
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
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Name field (editable for non-federated users)
                            TextFormField(
                              controller: _nameController,
                              enabled: !_isFederatedUser,
                              decoration: InputDecoration(
                                labelText: 'Display Name',
                                prefixIcon: Icon(Icons.badge),
                                hintText: _isFederatedUser 
                                  ? 'Managed by your $_federatedProvider account'
                                  : 'Enter your preferred name',
                                suffixIcon: _isFederatedUser
                                  ? Tooltip(
                                      message: 'Display name is managed by your $_federatedProvider account and cannot be changed here',
                                      child: Icon(
                                        Icons.info_outline,
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                      ),
                                    )
                                  : null,
                              ),
                              style: _isFederatedUser
                                ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  )
                                : null,
                              validator: (value) {
                                if (!_isFederatedUser && (value == null || value.trim().isEmpty)) {
                                  return 'Please enter your display name';
                                }
                                return null;
                              },
                            ),
                            
                            // Show info message for federated users
                            if (_isFederatedUser) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$_federatedProvider Account User',
                                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                              color: Theme.of(context).colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Your display name is managed by your $_federatedProvider account. To change it, update your name in your $_federatedProvider account settings, then sign out and sign back in.',
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                        ],
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
                                // Auto-save subscription changes immediately
                                _autoSaveProfile(showSnackbar: true);
                              },
                              activeThumbColor: Theme.of(context).colorScheme.primary,
                              contentPadding: EdgeInsets.zero,
                            ),
                            
                            // Notification preferences (only show if subscribed)
                            if (_subscribeToDailyNuggets) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Notification Preferences',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              
                              // Email notifications
                              SwitchListTile(
                                title: Row(
                                  children: [
                                    Icon(
                                      Icons.email,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Email Notifications',
                                      style: Theme.of(context).textTheme.bodyLarge,
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  'Receive quotes in your inbox daily',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                value: _enableEmailNotifications,
                                onChanged: (value) {
                                  setState(() {
                                    _enableEmailNotifications = value;
                                  });
                                  _autoSaveProfile(showSnackbar: true);
                                },
                                activeThumbColor: Theme.of(context).colorScheme.primary,
                                contentPadding: const EdgeInsets.only(left: 8),
                              ),
                              
                              // Push notifications (mobile only)
                              if (!kIsWeb) ...[
                                SwitchListTile(
                                  title: Row(
                                    children: [
                                      Icon(
                                        Icons.notifications,
                                        color: _pushPermissionsGranted 
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Push Notifications',
                                        style: Theme.of(context).textTheme.bodyLarge,
                                      ),
                                      if (!_pushPermissionsGranted) ...[
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: _isRequestingPushPermissions ? null : _requestPushPermissions,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                              ),
                                            ),
                                            child: _isRequestingPushPermissions
                                              ? Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        valueColor: AlwaysStoppedAnimation<Color>(
                                                          Theme.of(context).colorScheme.primary,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'Enabling...',
                                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                        color: Theme.of(context).colorScheme.primary,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : Text(
                                                  'Tap to Enable',
                                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                    color: Theme.of(context).colorScheme.primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    _pushPermissionsGranted 
                                      ? 'Get notified directly on your device'
                                      : 'Tap "Tap to Enable" to grant notification permissions',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  value: _enablePushNotifications && _pushPermissionsGranted,
                                  onChanged: (value) async {
                                    if (value && !_pushPermissionsGranted) {
                                      // If trying to enable but permissions not granted, request them
                                      await _requestPushPermissions();
                                    } else {
                                      // Normal toggle behavior
                                      setState(() {
                                        _enablePushNotifications = value;
                                      });
                                      _autoSaveProfile(showSnackbar: true);
                                    }
                                  },
                                  activeThumbColor: Theme.of(context).colorScheme.primary,
                                  contentPadding: const EdgeInsets.only(left: 8),
                                ),
                              ],
                              
                              const SizedBox(height: 16),
                              
                              // Timezone and time selection
                              Text(
                                'Delivery Schedule',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              
                              // Preferred time selection
                              DropdownButtonFormField<String>(
                                initialValue: _preferredTime,
                                decoration: InputDecoration(
                                  labelText: 'Preferred Time',
                                  prefixIcon: Icon(Icons.schedule),
                                  helperText: 'Choose your preferred delivery time',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                items: _availableHours.map((String time) {
                                  final hour24 = int.parse(time.split(':')[0]);
                                  final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
                                  final period = hour24 < 12 ? 'AM' : 'PM';
                                  
                                  return DropdownMenuItem<String>(
                                    value: time,
                                    child: Text('$hour12:00 $period'),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      _preferredTime = newValue;
                                    });
                                    _autoSaveProfile(showSnackbar: true);
                                  }
                                },
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Timezone selection
                              DropdownButtonFormField<String>(
                                initialValue: _selectedTimezone,
                                decoration: InputDecoration(
                                  labelText: 'Your Timezone',
                                  prefixIcon: Icon(Icons.public),
                                  helperText: 'Quotes will be delivered at ${_getFormattedTime()} in your local time',
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
                                    _autoSaveProfile(showSnackbar: true);
                                  }
                                },
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Test Email Button
                              if (_subscribeToDailyNuggets && _enableEmailNotifications) ...[
                                Center(
                                  child: OutlinedButton.icon(
                                    onPressed: _isSendingTestEmail ? null : _sendTestEmail,
                                    icon: _isSendingTestEmail 
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.email_outlined),
                                    label: Text(_isSendingTestEmail ? 'Sending...' : 'Send Test Email'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              
                              // Test Push Notification Button  
                              if (_subscribeToDailyNuggets && _enablePushNotifications && _pushPermissionsGranted) ...[
                                Center(
                                  child: OutlinedButton.icon(
                                    onPressed: _isSendingTestNotification ? null : _sendTestNotification,
                                    icon: _isSendingTestNotification 
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.notifications_outlined),
                                    label: Text(_isSendingTestNotification ? 'Sending...' : 'Send Test Notification'),
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
                                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
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
                                        'Daily nuggets will be delivered every day at ${_format12Hour(_preferredTime)} in your local timezone.',
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
                    
                    // Auto-save indicator
                    if (_isSaving)
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Saving changes...',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Center(
                        child: Text(
                          'Changes save automatically',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
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