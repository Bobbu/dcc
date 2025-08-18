import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../themes.dart';

class SettingsScreen extends StatefulWidget {
  final bool audioEnabled;
  final Set<String> selectedCategories;
  final Map<String, String>? selectedVoice;
  final double speechRate;
  final double pitch;
  final Function(bool, Set<String>, Map<String, String>?, double, double) onSettingsChanged;

  const SettingsScreen({
    super.key,
    required this.audioEnabled,
    required this.selectedCategories,
    this.selectedVoice,
    this.speechRate = 0.5,
    this.pitch = 1.0,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _audioEnabled;
  late Set<String> _selectedCategories;
  Map<String, String>? _selectedVoice;
  late double _speechRate;
  late double _pitch;
  List<Map<String, dynamic>> _availableVoices = [];
  bool _voicesLoaded = false;
  late FlutterTts _testTts;
  bool _isTestSpeaking = false;
  
  // Categories/Tags management
  List<String> _availableCategories = [];
  bool _categoriesLoaded = false;
  
  static const List<String> _fallbackCategories = [
    'All', 'Sports', 'Education', 'Science', 'Motivation', 'Funny', 'Persistence', 'Business'
  ];

  @override
  void initState() {
    super.initState();
    _audioEnabled = widget.audioEnabled;
    _selectedCategories = Set<String>.from(widget.selectedCategories);
    _selectedVoice = widget.selectedVoice;
    _speechRate = widget.speechRate;
    _pitch = widget.pitch;
    
    // Initialize test TTS
    _testTts = FlutterTts();
    _initTestTts();
    _loadAvailableVoices();
    
    // Load categories/tags
    _loadCategories();
  }
  
  @override
  void dispose() {
    _testTts.stop();
    super.dispose();
  }
  
  void _initTestTts() {
    _testTts.setStartHandler(() {
      setState(() {
        _isTestSpeaking = true;
      });
    });

    _testTts.setCompletionHandler(() {
      setState(() {
        _isTestSpeaking = false;
      });
    });

    _testTts.setErrorHandler((msg) {
      setState(() {
        _isTestSpeaking = false;
      });
    });
  }
  
  Future<void> _loadAvailableVoices() async {
    try {
      List<dynamic> voices = await _testTts.getVoices;
      setState(() {
        _availableVoices = voices.map((voice) => Map<String, dynamic>.from(voice)).toList();
        _voicesLoaded = true;
        
        // Auto-select Daniel voice if available and no voice is currently selected
        if (_selectedVoice == null && _availableVoices.isNotEmpty) {
          final danielVoice = _availableVoices.firstWhere(
            (voice) => voice['name']?.toString().toLowerCase() == 'daniel',
            orElse: () => <String, dynamic>{},
          );
          
          if (danielVoice.isNotEmpty) {
            _selectedVoice = {
              'name': danielVoice['name']?.toString() ?? '',
              'locale': danielVoice['locale']?.toString() ?? '',
            };
            // Trigger settings update to save the default voice
            widget.onSettingsChanged(_audioEnabled, _selectedCategories, _selectedVoice, _speechRate, _pitch);
          }
        }
      });
    } catch (e) {
      LoggerService.error('Error loading voices', error: e);
      setState(() {
        _voicesLoaded = true;
      });
    }
  }
  
  Future<void> _loadCategories() async {
    try {
      LoggerService.debug('📋 Loading dynamic tags from public API...');
      
      // Load tags from public API (no authentication required)
      final apiTags = await ApiService.getTags();
      
      setState(() {
        _availableCategories = apiTags;
        _categoriesLoaded = true;
      });
      
      LoggerService.debug('✅ Loaded ${apiTags.length} dynamic tags: $apiTags');
      
    } catch (e) {
      LoggerService.error('❌ Failed to load dynamic tags, using fallback categories', error: e);
      
      // Use fallback categories if API fails
      setState(() {
        _availableCategories = List.from(_fallbackCategories);
        _categoriesLoaded = true;
      });
    }
  }

  void _updateSettings() {
    widget.onSettingsChanged(_audioEnabled, _selectedCategories, _selectedVoice, _speechRate, _pitch);
  }
  
  // Helper methods for TTS options
  String _getSpeechRateLabel(double rate) {
    if (rate <= 0.2) return 'Very Slow';
    if (rate <= 0.5) return 'Moderate';
    if (rate <= 0.6) return 'Normal';
    return 'Fast';
  }
  
  String _getPitchLabel(double pitch) {
    if (pitch < 0.9) return 'Low';
    if (pitch > 1.1) return 'High';
    return 'Normal';
  }
  
  double _getSpeechRateValue(String label) {
    switch (label) {
      case 'Very Slow': return 0.15;
      case 'Moderate': return 0.45;
      case 'Normal': return 0.55;
      case 'Fast': return 0.75;
      default: return 0.55;
    }
  }
  
  double _getPitchValue(String label) {
    switch (label) {
      case 'Low': return 0.6;
      case 'Normal': return 1.0;
      case 'High': return 1.4;
      default: return 1.0;
    }
  }
  
  Future<void> _testVoice(Map<String, String> voice) async {
    try {
      await _testTts.stop();
      await _testTts.setVoice(voice);
      await _testTts.setSpeechRate(_speechRate);
      await _testTts.setPitch(_pitch);
      await _testTts.speak("Hello! This is a test of the ${voice['name']} voice.");
    } catch (e) {
      LoggerService.error('Error testing voice', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFE8EAF6), // Light indigo
              const Color(0xFFE8EAF6), // Light indigo (consistent)
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Audio Settings Section
            Card(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      const Color(0xFFE8EAF6).withValues(alpha: 77),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.volume_up,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Audio Settings',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: Text(
                          'Enable Audio Playback',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        subtitle: Text(
                          'Automatically read quotes aloud when loaded',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        value: _audioEnabled,
                        activeThumbColor: Theme.of(context).colorScheme.primary,
                        onChanged: (value) {
                          setState(() {
                            _audioEnabled = value;
                          });
                          _updateSettings();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Voice Selection Section
            Card(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      const Color(0xFFE8EAF6).withValues(alpha: 77),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.record_voice_over,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Voice Selection',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose a voice for text-to-speech',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      if (!_voicesLoaded)
                        const Center(child: CircularProgressIndicator())
                      else if (_availableVoices.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            border: Border.all(color: Colors.orange.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'No voices available on this device',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.orange.shade700,
                            ),
                          ),
                        )
                      else
                        Column(
                          children: [
                            // Current selection
                            if (_selectedVoice != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Theme.of(context).colorScheme.onPrimary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Current: ${_selectedVoice!['name']} (${_selectedVoice!['locale']})',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.onPrimary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),
                            // Voice list
                            Container(
                              constraints: const BoxConstraints(maxHeight: 300),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: _availableVoices.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final voice = _availableVoices[index];
                                  final voiceMap = {
                                    'name': voice['name']?.toString() ?? 'Unknown',
                                    'locale': voice['locale']?.toString() ?? 'Unknown',
                                  };
                                  final isSelected = _selectedVoice?['name'] == voiceMap['name'] &&
                                      _selectedVoice?['locale'] == voiceMap['locale'];
                                  
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      voiceMap['name']!,
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      voiceMap['locale']!,
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                    leading: Icon(
                                      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedVoice = voiceMap;
                                      });
                                      _updateSettings();
                                    },
                                    trailing: IconButton(
                                      icon: Icon(
                                        _isTestSpeaking ? Icons.stop : Icons.play_arrow,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      onPressed: () => _testVoice(voiceMap),
                                      tooltip: 'Test Voice',
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Speech Rate Section
            Card(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      const Color(0xFFE8EAF6).withValues(alpha: 77),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.speed,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Speech Rate',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Control how fast the voice speaks',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: ['Very Slow', 'Moderate', 'Normal', 'Fast'].map((label) {
                          final isSelected = _getSpeechRateLabel(_speechRate) == label;
                          return ChoiceChip(
                            label: Text(label),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _speechRate = _getSpeechRateValue(label);
                                });
                                _updateSettings();
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Pitch Section
            Card(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      const Color(0xFFE8EAF6).withValues(alpha: 77),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.tune,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Voice Pitch',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Adjust the pitch/tone of the voice',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: ['Low', 'Normal', 'High'].map((label) {
                          final isSelected = _getPitchLabel(_pitch) == label;
                          return ChoiceChip(
                            label: Text(label),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _pitch = _getPitchValue(label);
                                });
                                _updateSettings();
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Quote Categories Section
            Card(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white,
                      const Color(0xFFE8EAF6).withValues(alpha: 77),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.category,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Quote Categories',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select the types of quotes you\'d like to see',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      // Show warning if less than 3 categories selected and not "All"
                      if (!_selectedCategories.contains('All') && _selectedCategories.length < 3)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            border: Border.all(color: Colors.orange.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Please select at least 3 categories or "All" to ensure variety',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (!_categoriesLoaded)
                        const Center(child: CircularProgressIndicator())
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 51),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 153),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.cloud_sync,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Dynamic tags loaded from server',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _availableCategories.map((category) {
                          final isSelected = _selectedCategories.contains(category);
                          final isAll = category == 'All';
                          
                          return FilterChip(
                            label: Text(category),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (isAll) {
                                  if (selected) {
                                    _selectedCategories.clear();
                                    _selectedCategories.add('All');
                                  } else {
                                    _selectedCategories.remove('All');
                                    // If user unchecks "All" and no other categories are selected,
                                    // we need at least one category, so re-add "All"
                                    if (_selectedCategories.isEmpty) {
                                      _selectedCategories.add('All');
                                    }
                                  }
                                } else {
                                  if (selected) {
                                    _selectedCategories.remove('All');
                                    _selectedCategories.add(category);
                                  } else {
                                    // Check if deselecting would leave us with less than 3 categories
                                    final remainingCategories = _selectedCategories
                                        .where((cat) => cat != category && cat != 'All')
                                        .length;
                                    
                                    if (remainingCategories < 3) {
                                      // Show a snackbar message and don't allow deselection
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text(
                                            'Please keep at least 3 categories selected for variety, or select "All"',
                                          ),
                                          backgroundColor: Colors.orange.shade700,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                      return; // Don't allow deselection
                                    }
                                    
                                    _selectedCategories.remove(category);
                                    // If no specific categories are selected, auto-select "All"
                                    final hasSpecificCategories = _selectedCategories
                                        .where((cat) => cat != 'All')
                                        .isNotEmpty;
                                    if (!hasSpecificCategories) {
                                      _selectedCategories.clear();
                                      _selectedCategories.add('All');
                                    }
                                  }
                                }
                              });
                              _updateSettings();
                            },
                          );
                              }).toList(),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}