import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';
import '../themes.dart';

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
  
  @override
  void initState() {
    super.initState();
    _loadUserProfile();
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
      
      // Load subscription preferences from SharedPreferences (user-scoped)
      final prefs = await SharedPreferences.getInstance();
      final userPrefix = email != null ? '${email}_' : 'default_';
      final subscribeToDailyNuggets = prefs.getBool('${userPrefix}subscribe_daily_nuggets') ?? false;
      final deliveryMethod = prefs.getString('${userPrefix}delivery_method') ?? 'email';
      
      setState(() {
        _userEmail = email;
        _userName = name;
        _nameController.text = name ?? '';
        _subscribeToDailyNuggets = subscribeToDailyNuggets;
        _deliveryMethod = deliveryMethod;
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
      
      // Save subscription preferences to SharedPreferences (local only for now, user-scoped)
      final prefs = await SharedPreferences.getInstance();
      final userPrefix = _userEmail != null ? '${_userEmail}_' : 'default_';
      await prefs.setBool('${userPrefix}subscribe_daily_nuggets', _subscribeToDailyNuggets);
      await prefs.setString('${userPrefix}delivery_method', _deliveryMethod);
      
      LoggerService.info('✅ Profile saved successfully');
      LoggerService.info('   Name: ${_nameController.text.trim()}');
      LoggerService.info('   Subscribe to Daily Nuggets: $_subscribeToDailyNuggets');
      LoggerService.info('   Delivery Method: $_deliveryMethod');
      
      // Update local state
      setState(() {
        _userName = newName;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved! Daily nugget preferences are stored locally and will sync with backend when implemented.'),
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
                              
                              // Notifications option
                              RadioListTile<String>(
                                title: Row(
                                  children: [
                                    Icon(
                                      Icons.notifications,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Push Notifications',
                                      style: Theme.of(context).textTheme.bodyLarge,
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  'Get notified directly on your device',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                value: 'notifications',
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