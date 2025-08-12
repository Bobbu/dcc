import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SettingsScreen extends StatefulWidget {
  final bool audioEnabled;
  final Set<String> selectedCategories;
  final Map<String, String>? selectedVoice;
  final Function(bool, Set<String>, Map<String, String>?) onSettingsChanged;

  const SettingsScreen({
    super.key,
    required this.audioEnabled,
    required this.selectedCategories,
    this.selectedVoice,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _audioEnabled;
  late Set<String> _selectedCategories;
  Map<String, String>? _selectedVoice;
  List<Map<String, dynamic>> _availableVoices = [];
  bool _voicesLoaded = false;
  late FlutterTts _testTts;
  bool _isTestSpeaking = false;
  
  static const List<String> _availableCategories = [
    'All', 'Sports', 'Education', 'Science', 'Motivation', 'Funny', 'Persistence', 'Business'
  ];

  @override
  void initState() {
    super.initState();
    _audioEnabled = widget.audioEnabled;
    _selectedCategories = Set<String>.from(widget.selectedCategories);
    _selectedVoice = widget.selectedVoice;
    
    // Initialize test TTS
    _testTts = FlutterTts();
    _initTestTts();
    _loadAvailableVoices();
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
      });
    } catch (e) {
      print('Error loading voices: $e');
      setState(() {
        _voicesLoaded = true;
      });
    }
  }

  void _updateSettings() {
    widget.onSettingsChanged(_audioEnabled, _selectedCategories, _selectedVoice);
  }
  
  Future<void> _testVoice(Map<String, String> voice) async {
    try {
      await _testTts.stop();
      await _testTts.setVoice(voice);
      await _testTts.speak("Hello! This is a test of the ${voice['name']} voice.");
    } catch (e) {
      print('Error testing voice: $e');
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
              const Color(0xFFFFF8DC), // Cream
              const Color(0xFFFFFAF0), // Slightly lighter cream
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
                      const Color(0xFFFFF8DC).withOpacity(0.3),
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
                              color: const Color(0xFF800000),
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
                            color: const Color(0xFF800000),
                          ),
                        ),
                        subtitle: Text(
                          'Automatically read quotes aloud when loaded',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF800000).withOpacity(0.7),
                          ),
                        ),
                        value: _audioEnabled,
                        activeColor: Theme.of(context).colorScheme.primary,
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
                      const Color(0xFFFFF8DC).withOpacity(0.3),
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
                              color: const Color(0xFF800000),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose a voice for text-to-speech',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF800000).withOpacity(0.7),
                        ),
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
                                  color: const Color(0xFFFFD700).withOpacity(0.1),
                                  border: Border.all(
                                    color: const Color(0xFFFFD700).withOpacity(0.3),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Current: ${_selectedVoice!['name']} (${_selectedVoice!['locale']})',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: const Color(0xFF800000),
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
                                      style: TextStyle(
                                        color: const Color(0xFF800000),
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Text(
                                      voiceMap['locale']!,
                                      style: TextStyle(
                                        color: const Color(0xFF800000).withOpacity(0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                    leading: Radio<String>(
                                      value: '${voiceMap['name']}_${voiceMap['locale']}',
                                      groupValue: _selectedVoice != null 
                                          ? '${_selectedVoice!['name']}_${_selectedVoice!['locale']}'
                                          : null,
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedVoice = voiceMap;
                                        });
                                        _updateSettings();
                                      },
                                      activeColor: Theme.of(context).colorScheme.primary,
                                    ),
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
                      const Color(0xFFFFF8DC).withOpacity(0.3),
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
                              color: const Color(0xFF800000),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select the types of quotes you\'d like to see',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF800000).withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFFFD700).withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          'Note: Category filtering will be implemented in a future update. Currently all quotes are shown regardless of selection.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF800000).withOpacity(0.6),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableCategories.map((category) {
                          final isSelected = _selectedCategories.contains(category);
                          final isAllSelected = _selectedCategories.contains('All');
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
                            selectedColor: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
                            checkmarkColor: Theme.of(context).colorScheme.primary,
                            labelStyle: TextStyle(
                              color: isSelected 
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.primary.withOpacity(0.7),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }).toList(),
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