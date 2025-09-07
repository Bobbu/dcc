import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';
import '../services/daily_nuggets_service.dart';
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
  
  @override
  void initState() {
    super.initState();
    _checkAuthenticationAndLoad();
    
    // Add listener for name changes with debouncing
    _nameController.addListener(_onNameChanged);
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
      
      // Save subscription preferences to backend
      await DailyNuggetsService.updateSubscription(
        isSubscribed: _subscribeToDailyNuggets,
        deliveryMethod: _deliveryMethod,
        timezone: _selectedTimezone,
      );
      
      _hasUnsavedChanges = false;
      
      LoggerService.info('✅ Profile auto-saved successfully');
      
      if (showSnackbar && mounted) {
        final message = _subscribeToDailyNuggets 
          ? 'Changes saved! Daily quotes at 8 AM ${_selectedTimezone.split('/').last.replaceAll('_', ' ')} time.'
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
                            
                            // Delivery method selection (only show if subscribed)
                            if (_subscribeToDailyNuggets) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Delivery Method',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              
                              // Delivery Method Selection
                              Column(
                                children: [
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
                                        // Auto-save delivery method changes immediately
                                        _autoSaveProfile(showSnackbar: true);
                                      }
                                    },
                                    contentPadding: const EdgeInsets.only(left: 8),
                                  ),
                                  
                                  // Notifications option (disabled for now)
                                  RadioListTile<String>(
                                    title: Row(
                                      children: [
                                        Icon(
                                          Icons.notifications,
                                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Push Notifications',
                                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
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
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    value: 'notifications',
                                    groupValue: _deliveryMethod,
                                    onChanged: null, // Disabled - cannot be selected
                                    contentPadding: const EdgeInsets.only(left: 8),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Timezone selection
                              Text(
                                'Delivery Time',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedTimezone,
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
                                    // Auto-save timezone changes immediately
                                    _autoSaveProfile(showSnackbar: true);
                                  }
                                },
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Test Email Button
                              if (_subscribeToDailyNuggets && _deliveryMethod == 'email') ...[
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