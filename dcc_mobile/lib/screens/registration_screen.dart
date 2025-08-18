import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/logger_service.dart';
import '../themes.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _confirmationCodeController = TextEditingController();
  
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _showConfirmationForm = false;
  String? _errorMessage;
  String? _registeredEmail;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _confirmationCodeController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null || apiUrl.isEmpty) {
        setState(() {
          _errorMessage = 'Configuration error. Please restart the app.';
        });
        return;
      }
      
      LoggerService.debug('Attempting registration to: $apiUrl/auth/register');
      final response = await http.post(
        Uri.parse('$apiUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'name': _nameController.text.trim(),
        }),
      );

      LoggerService.debug('Registration response: ${response.statusCode}');
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _showConfirmationForm = true;
          _registeredEmail = _emailController.text.trim();
          _errorMessage = null;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registration successful! Please check your email for the verification code.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = data['error'] ?? 'Registration failed';
        });
      }
    } catch (e) {
      LoggerService.error('Registration error', error: e);
      setState(() {
        _errorMessage = 'Network error. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmEmail() async {
    if (_confirmationCodeController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter the confirmation code';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiUrl = dotenv.env['API_URL'];
      if (apiUrl == null || apiUrl.isEmpty) {
        setState(() {
          _errorMessage = 'Configuration error. Please restart the app.';
        });
        return;
      }
      
      LoggerService.debug('Attempting confirmation to: $apiUrl/auth/confirm');
      final response = await http.post(
        Uri.parse('$apiUrl/auth/confirm'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _registeredEmail,
          'code': _confirmationCodeController.text.trim(),
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email confirmed! You can now sign in.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _errorMessage = data['error'] ?? 'Confirmation failed';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain an uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain a lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain a number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Password must contain a special character';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF3F51B5), // Indigo
              const Color(0xFF5C6BC0), // Light indigo
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // App Logo/Title
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 77),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.person_add,
                          size: 64,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _showConfirmationForm ? 'Verify Email' : 'Join Quote Me',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Registration/Confirmation Form
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 25),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: _showConfirmationForm
                        ? _buildConfirmationForm()
                        : _buildRegistrationForm(),
                  ),

                  const SizedBox(height: 32),

                  // Back Button
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_back,
                          color: Colors.white.withValues(alpha: 204),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Back to Sign In',
                          style: AppThemes.linkText(context).copyWith(color: Colors.white.withValues(alpha: 204)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegistrationForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create Account',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: const Color(0xFF3F51B5),
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          // Name Field
          TextFormField(
            controller: _nameController,
            enabled: !_isLoading,
            decoration: InputDecoration(
              labelText: 'Full Name (Optional)',
              prefixIcon: const Icon(Icons.person),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF3F51B5),
                  width: 2,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Email Field
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            enabled: !_isLoading,
            decoration: InputDecoration(
              labelText: 'Email Address',
              prefixIcon: const Icon(Icons.email),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF3F51B5),
                  width: 2,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email address';
              }
              if (!value.contains('@')) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),

          const SizedBox(height: 16),

          // Password Field
          TextFormField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            enabled: !_isLoading,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _isPasswordVisible = !_isPasswordVisible;
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF3F51B5),
                  width: 2,
                ),
              ),
              helperText: 'Min 8 chars, uppercase, lowercase, number, special char',
              helperMaxLines: 2,
            ),
            validator: _validatePassword,
          ),

          const SizedBox(height: 16),

          // Confirm Password Field
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: !_isConfirmPasswordVisible,
            enabled: !_isLoading,
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF3F51B5),
                  width: 2,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),

          const SizedBox(height: 24),

          // Error Message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: AppThemes.errorText(context),
                    ),
                  ),
                ],
              ),
            ),

          // Sign Up Button
          ElevatedButton(
            onPressed: _isLoading ? null : _register,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3F51B5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: _isLoading
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text('Creating Account...'),
                    ],
                  )
                : Text(
                    'Create Account',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Verify Your Email',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: const Color(0xFF3F51B5),
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 16),

        Text(
          'We sent a verification code to:',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _registeredEmail ?? '',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 24),

        // Confirmation Code Field
        TextFormField(
          controller: _confirmationCodeController,
          keyboardType: TextInputType.number,
          enabled: !_isLoading,
          decoration: InputDecoration(
            labelText: 'Verification Code',
            prefixIcon: const Icon(Icons.security),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF3F51B5),
                width: 2,
              ),
            ),
            helperText: 'Enter the 6-digit code from your email',
          ),
        ),

        const SizedBox(height: 24),

        // Error Message
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.red.shade700,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: AppThemes.errorText(context),
                  ),
                ),
              ],
            ),
          ),

        // Confirm Button
        ElevatedButton(
          onPressed: _isLoading ? null : _confirmEmail,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
          child: _isLoading
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text('Verifying...'),
                  ],
                )
              : Text(
                  'Verify Email',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
        ),

        const SizedBox(height: 16),

        // Back to Registration Button
        TextButton(
          onPressed: _isLoading ? null : () {
            setState(() {
              _showConfirmationForm = false;
              _errorMessage = null;
            });
          },
          child: Text(
            'Back to Registration',
            style: AppThemes.linkText(context).copyWith(fontSize: 14),
          ),
        ),
      ],
    );
  }
}