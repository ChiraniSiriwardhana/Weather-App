import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Personalized Weather Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        cardTheme: CardTheme(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const WeatherHomePage(),
    );
  }
}

class WeatherHomePage extends StatefulWidget {
  const WeatherHomePage({super.key});

  @override
  State<WeatherHomePage> createState() => _WeatherHomePageState();
}

class _WeatherHomePageState extends State<WeatherHomePage> with SingleTickerProviderStateMixin {
  final TextEditingController _indexController = TextEditingController(text: '224229M');
  bool _loading = false;
  String? _error;
  double? _latitude;
  double? _longitude;
  String? _requestUrl;
  double? _temperature;
  double? _windSpeed;
  int? _weatherCode;
  DateTime? _lastUpdated;
  bool _isCached = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  static const String _cacheKey = 'cached_weather_json';
  static const String _cacheTimeKey = 'cached_weather_time';
  static const String _cacheIndexKey = 'cached_index';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _loadCachedIfAny();
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _indexController.dispose();
    super.dispose();
  }

  bool _deriveCoordsFromIndex(String index) {
    _error = null;
    _isCached = false;
    index = index.trim();
    if (index.length < 4) {
      _error = 'Index must have at least 4 characters (digits).';
      return false;
    }
    try {
      final firstTwoStr = index.substring(0, 2);
      final nextTwoStr = index.substring(2, 4);
      final firstTwo = int.parse(firstTwoStr);
      final nextTwo = int.parse(nextTwoStr);

      final lat = 5 + (firstTwo / 10.0);
      final lon = 79 + (nextTwo / 10.0);

      _latitude = double.parse(lat.toStringAsFixed(2));
      _longitude = double.parse(lon.toStringAsFixed(2));
      _requestUrl = 'https://api.open-meteo.com/v1/forecast?latitude=$_latitude&longitude=$_longitude&current_weather=true';
      return true;
    } catch (e) {
      _error = 'Invalid index format — first 4 characters must be digits.';
      return false;
    }
  }

  void _showErrorDialog(String errorMessage, {bool showCachedInfo = false}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                showCachedInfo ? Icons.offline_bolt : Icons.error_outline,
                color: showCachedInfo ? Colors.orange : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  showCachedInfo ? 'Network Error' : 'Error',
                  style: TextStyle(
                    color: showCachedInfo ? Colors.orange.shade700 : Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                errorMessage,
                style: const TextStyle(fontSize: 15),
              ),
              if (showCachedInfo) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Showing cached data from last successful fetch',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchWeather() async {
    setState(() {
      _loading = true;
      _error = null;
      _isCached = false;
    });

    final index = _indexController.text;
    final ok = _deriveCoordsFromIndex(index);
    if (!ok) {
      setState(() {
        _loading = false;
      });
      _showErrorDialog(_error!);
      return;
    }

    final url = Uri.parse(_requestUrl!);

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        if (body['current_weather'] == null) {
          throw Exception('No current_weather in response');
        }
        final cw = body['current_weather'] as Map<String, dynamic>;

        final temp = (cw['temperature'] != null) ? (cw['temperature'] as num).toDouble() : null;
        final wind = (cw['windspeed'] != null) ? (cw['windspeed'] as num).toDouble() : null;
        final code = (cw['weathercode'] != null) ? (cw['weathercode'] as num).toInt() : null;

        setState(() {
          _temperature = temp;
          _windSpeed = wind;
          _weatherCode = code;
          _lastUpdated = DateTime.now();
          _isCached = false;
          _error = null;
        });

        final prefs = await SharedPreferences.getInstance();
        final cacheObj = {
          'index': index,
          'latitude': _latitude,
          'longitude': _longitude,
          'current_weather': cw,
          'cached_at': _lastUpdated!.toIso8601String(),
        };
        await prefs.setString(_cacheKey, json.encode(cacheObj));
        await prefs.setString(_cacheTimeKey, _lastUpdated!.toIso8601String());
        await prefs.setString(_cacheIndexKey, index);

        _animController.reset();
        _animController.forward();
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      final loaded = await _loadCachedIfAny();
      String errorMsg = 'Failed to fetch weather data.\n\n';

      if (e.toString().contains('SocketException') ||
          e.toString().contains('NetworkException') ||
          e.toString().contains('TimeoutException')) {
        errorMsg += 'Please check your internet connection and try again.';
      } else {
        errorMsg += 'Error: ${e.toString()}';
      }

      setState(() {
        _error = errorMsg;
        if (!loaded) {
          _temperature = null;
          _windSpeed = null;
          _weatherCode = null;
        } else {
          _isCached = true;
        }
      });

      // Show error dialog
      _showErrorDialog(errorMsg, showCachedInfo: loaded);
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<bool> _loadCachedIfAny() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_cacheKey)) return false;
    try {
      final cached = prefs.getString(_cacheKey);
      if (cached == null) return false;
      final Map<String, dynamic> obj = json.decode(cached);
      final cw = obj['current_weather'] as Map<String, dynamic>?;

      setState(() {
        _indexController.text = obj['index']?.toString() ?? _indexController.text;
        _latitude = (obj['latitude'] != null) ? (obj['latitude'] as num).toDouble() : null;
        _longitude = (obj['longitude'] != null) ? (obj['longitude'] as num).toDouble() : null;
        if (cw != null) {
          _temperature = (cw['temperature'] != null) ? (cw['temperature'] as num).toDouble() : null;
          _windSpeed = (cw['windspeed'] != null) ? (cw['windspeed'] as num).toDouble() : null;
          _weatherCode = (cw['weathercode'] != null) ? (cw['weathercode'] as num).toInt() : null;
        }
        final cachedAt = obj['cached_at']?.toString();
        _lastUpdated = cachedAt != null ? DateTime.tryParse(cachedAt) : null;
        _isCached = true;
        _requestUrl = 'https://api.open-meteo.com/v1/forecast?latitude=$_latitude&longitude=$_longitude&current_weather=true';
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  IconData _getWeatherIcon() {
    if (_weatherCode == null) return Icons.cloud_outlined;
    if (_weatherCode == 0) return Icons.wb_sunny;
    if (_weatherCode! <= 3) return Icons.cloud;
    if (_weatherCode! <= 67) return Icons.cloud_queue;
    if (_weatherCode! <= 77) return Icons.ac_unit;
    if (_weatherCode! <= 99) return Icons.thunderstorm;
    return Icons.cloud_outlined;
  }

  Color _getWeatherColor() {
    if (_weatherCode == null) return Colors.grey;
    if (_weatherCode == 0) return Colors.orange;
    if (_weatherCode! <= 3) return Colors.blue.shade300;
    if (_weatherCode! <= 67) return Colors.blue.shade600;
    if (_weatherCode! <= 77) return Colors.cyan;
    return Colors.deepPurple;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.secondaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Text(
                  '🌤️ Weather Dashboard',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'IN3510 Assignment',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Input Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Student Index',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _indexController,
                          decoration: InputDecoration(
                            hintText: 'e.g., 224229M',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                          ),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _loading ? null : _fetchWeather,
                            icon: _loading
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Icon(Icons.cloud_download),
                            label: Text(
                              _loading ? 'Fetching...' : 'Fetch Weather',
                              style: const TextStyle(fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Coordinates Card
                if (_latitude != null && _longitude != null)
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  color: theme.colorScheme.primary,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Location Coordinates',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              'Latitude',
                              '${_latitude!.toStringAsFixed(2)}°',
                              Icons.arrow_upward,
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'Longitude',
                              '${_longitude!.toStringAsFixed(2)}°',
                              Icons.arrow_forward,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // Weather Data Card
                if (_temperature != null || _isCached)
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Card(
                      color: _getWeatherColor().withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Current Weather',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_isCached)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.orange.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.offline_bolt,
                                          size: 16,
                                          color: Colors.orange.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'CACHED',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Icon(
                              _getWeatherIcon(),
                              size: 80,
                              color: _getWeatherColor(),
                            ),
                            const SizedBox(height: 20),
                            if (_temperature != null)
                              Text(
                                '${_temperature!.toStringAsFixed(1)}°C',
                                style: theme.textTheme.displayLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _getWeatherColor(),
                                ),
                              ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildWeatherStat(
                                  Icons.air,
                                  'Wind Speed',
                                  _windSpeed != null
                                      ? '${_windSpeed!.toStringAsFixed(1)} km/h'
                                      : '-',
                                ),
                                _buildWeatherStat(
                                  Icons.code,
                                  'Weather Code',
                                  _weatherCode?.toString() ?? '-',
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 18,
                                    color: Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _lastUpdated != null
                                          ? 'Updated: ${_formatDateTime(_lastUpdated!)}'
                                          : 'No data yet',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // Request URL Card
                if (_requestUrl != null)
                  Card(
                    color: Colors.grey.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.link,
                                size: 16,
                                color: Colors.grey.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Request URL',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _requestUrl!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),

                // Info text
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '💡 Tip: Enable Airplane Mode and tap "Fetch Weather" to see cached data when offline.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildWeatherStat(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.grey.shade700),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}