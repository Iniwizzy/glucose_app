import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'models/glucose_record.dart';
import 'screens/history_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'services/glucose_history_db.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with proper configuration
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glucose Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  String? _lastSyncedUid;

  Future<void> _syncProfileOnce() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid == _lastSyncedUid) return;
    _lastSyncedUid = uid;
    await _authService.ensureCurrentUserProfile();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData) {
          _lastSyncedUid = null;
          return LoginScreen();
        }

        // Fire-and-forget: sync profil di latar, tak blok build,
        // tak reset state GlucoseMonitorScreen saat rebuild (mis. gesture back).
        _syncProfileOnce();
        return const GlucoseMonitorScreen();
      },
    );
  }
}

class GlucoseMonitorScreen extends StatefulWidget {
  const GlucoseMonitorScreen({super.key});

  @override
  State<GlucoseMonitorScreen> createState() => GlucoseMonitorScreenState();
}

class GlucoseMonitorScreenState extends State<GlucoseMonitorScreen>
    with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final AuthService _authService = AuthService();
  final GlucoseHistoryDb _historyDb = GlucoseHistoryDb.instance;
  StreamSubscription<DatabaseEvent>? _glucoseSubscription;
  double glucoseValue = 0.0;
  String glucoseStatus = "Normal";
  bool isLoading = true;
  bool _historyLoading = true;
  List<GlucoseRecord> _recentHistory = [];
  double? _lastSavedValue;
  DateTime? _lastSavedAt;

  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;

  static const Color primaryColor = Color(
    0xFFB71C1C,
  ); // Bold Red (strong glucose indicator)
  static const Color secondaryColor = Color(0xFFFDECEC); // Light Red Background
  static const Color accentColor = Color(0xFF2E7D32); // Healthy Green

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _listenToGlucoseData();
    _initHistory();
  }

  Future<void> _initHistory() async {
    final userId = _currentUserId;
    if (userId != null) {
      try {
        await _historyDb.enforceRetentionPolicy(userId: userId, days: 90);
      } catch (e) {
        debugPrint('Retention policy failed: $e');
      }
    }

    await _loadRecentHistory();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _rotationController = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeInOut),
    );

    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _glucoseSubscription?.cancel();
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  void _listenToGlucoseData() {
    _glucoseSubscription?.cancel();
    _glucoseSubscription = _database
        .child('glucose_predict/prediction')
        .onValue
        .listen(
          (event) async {
            if (!event.snapshot.exists) return;

            final newValue = double.tryParse(event.snapshot.value.toString());
            if (newValue == null) return;

            final newStatus = _getGlucoseStatus(newValue);

            if (!mounted) return;
            setState(() {
              glucoseValue = newValue;
              glucoseStatus = newStatus;
              isLoading = false;
            });

            await _saveHistory(newValue, newStatus);
          },
          onError: (error) {
            debugPrint("Error listening to Firebase: $error");
            if (!mounted) return;
            setState(() {
              isLoading = false;
            });
          },
        );
  }

  Future<void> _saveHistory(double value, String status) async {
    final userId = _currentUserId;
    if (userId == null) return;

    final now = DateTime.now();
    final shouldSkipDuplicate =
        _lastSavedValue == value &&
        _lastSavedAt != null &&
        now.difference(_lastSavedAt!).inSeconds < 3;
    if (shouldSkipDuplicate) return;

    _lastSavedValue = value;
    _lastSavedAt = now;

    await _historyDb.insertRecord(
      GlucoseRecord(
        userId: userId,
        value: value,
        status: status,
        source: 'firebase_rtdb',
        notes: 'Auto saved from live prediction stream',
        measuredAt: now,
      ),
    );

    if (!mounted) return;
    await _loadRecentHistory();
  }

  Future<void> _loadRecentHistory() async {
    final userId = _currentUserId;
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
        _recentHistory = [];
      });
      return;
    }

    final records = await _historyDb.getRecentRecords(userId, limit: 5);
    if (!mounted) return;
    setState(() {
      _recentHistory = records;
      _historyLoading = false;
    });
  }

  String _getGlucoseStatus(double value) {
    if (value < 70) {
      return "Rendah";
    } else if (value >= 70 && value <= 140) {
      return "Normal";
    } else {
      return "Cukup Tinggi";
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "Rendah":
        return accentColor; // Deep orange for low
      case "Normal":
        return Color(0xFF2E7D32); // Green for normal
      case "Cukup Tinggi":
        return primaryColor; // Coral pink for high
      default:
        return Colors.grey;
    }
  }

  void _showHealthTips(String status) {
    String tips = "";
    switch (status) {
      case "Rendah":
        tips =
            "Tips untuk Glukosa Rendah:\n\n"
            "• Konsumsi makanan atau minuman yang mengandung gula sederhana\n"
            "• Makan permen atau tablet glukosa\n"
            "• Minum jus buah atau minuman manis\n"
            "• Istirahat dan periksa kembali dalam 15 menit\n"
            "• Segera hubungi dokter jika gejala berlanjut";
        break;
      case "Normal":
        tips =
            "Tips untuk Menjaga Glukosa Normal:\n\n"
            "• Pertahankan pola makan sehat dan teratur\n"
            "• Olahraga ringan secara rutin\n"
            "• Minum air putih yang cukup\n"
            "• Kelola stress dengan baik\n"
            "• Lakukan pemeriksaan rutin";
        break;
      case "Cukup Tinggi":
        tips =
            "Tips untuk Glukosa Tinggi:\n\n"
            "• Kurangi konsumsi makanan manis dan karbohidrat\n"
            "• Perbanyak minum air putih\n"
            "• Lakukan aktivitas fisik ringan\n"
            "• Konsumsi makanan berserat tinggi\n"
            "• Konsultasi dengan dokter untuk penanganan lebih lanjut";
        break;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: secondaryColor,
          title: Text(
            "Tips Kesehatan - $status",
            style: TextStyle(
              color: _getStatusColor(status),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Text(
            tips,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: accentColor.withOpacity(0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: _getStatusColor(status).withOpacity(0.1),
                foregroundColor: _getStatusColor(status),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  "Tutup",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    try {
      await _authService.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Berhasil keluar dari akun'),
          backgroundColor: accentColor,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal keluar dari akun: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: secondaryColor,
          title: Text(
            "Konfirmasi Keluar",
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Text(
            "Apakah Anda yakin ingin keluar dari akun?",
            style: TextStyle(fontSize: 16, color: accentColor.withOpacity(0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: Colors.grey.withOpacity(0.1),
                foregroundColor: Colors.grey[600],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  "Batal",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _logout();
              },
              style: TextButton.styleFrom(
                backgroundColor: primaryColor.withOpacity(0.1),
                foregroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  "Keluar",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openHistoryScreen() {
    final userId = _currentUserId;
    if (userId == null) return;

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => HistoryScreen(userId: userId)));
  }

  void _openProfileScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }

  Widget _buildRecentHistoryCard() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.92),
            Colors.white.withOpacity(0.65),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryColor.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.15),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HISTORY TERBARU',
                    style: TextStyle(
                      fontSize: 12,
                      color: accentColor.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tersimpan di SQLite lokal',
                    style: TextStyle(
                      fontSize: 13,
                      color: accentColor.withOpacity(0.65),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: _openHistoryScreen,
                child: Text('Lihat semua'),
              ),
            ],
          ),
          SizedBox(height: 14),
          if (_historyLoading)
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else if (_recentHistory.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Belum ada riwayat yang tersimpan.',
                style: TextStyle(
                  color: accentColor.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
            )
          else
            Column(
              children:
                  _recentHistory
                      .map(
                        (record) => Container(
                          margin: EdgeInsets.only(bottom: 10),
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(
                              record.status,
                            ).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _getStatusColor(
                                record.status,
                              ).withOpacity(0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _getStatusColor(record.status),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${record.value.toStringAsFixed(0)} mg/dL',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: accentColor,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      '${record.status} • ${record.measuredAt.toLocal()}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: accentColor.withOpacity(0.7),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildRecommendationButton(String buttonStatus, IconData icon) {
    bool isActive = glucoseStatus == buttonStatus;
    return LayoutBuilder(
      builder: (context, constraints) {
        double buttonSize = MediaQuery.of(context).size.width * 0.2;
        buttonSize = buttonSize.clamp(70.0, 90.0);

        return AnimatedContainer(
          duration: Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: GestureDetector(
            onTap: isActive ? () => _showHealthTips(buttonStatus) : null,
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                gradient:
                    isActive
                        ? LinearGradient(
                          colors: [
                            _getStatusColor(buttonStatus),
                            _getStatusColor(buttonStatus).withOpacity(0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                        : null,
                color: isActive ? null : secondaryColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      isActive
                          ? _getStatusColor(buttonStatus)
                          : accentColor.withOpacity(0.3),
                  width: 2,
                ),
                boxShadow:
                    isActive
                        ? [
                          BoxShadow(
                            color: _getStatusColor(
                              buttonStatus,
                            ).withOpacity(0.4),
                            blurRadius: 15,
                            spreadRadius: 2,
                            offset: Offset(0, 5),
                          ),
                        ]
                        : [
                          BoxShadow(
                            color: accentColor.withOpacity(0.2),
                            blurRadius: 10,
                            spreadRadius: 1,
                            offset: Offset(0, 4),
                          ),
                        ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color:
                        isActive ? Colors.white : accentColor.withOpacity(0.8),
                    size: buttonSize * 0.35,
                  ),
                  SizedBox(height: 4),
                  Text(
                    buttonStatus.toUpperCase(),
                    style: TextStyle(
                      color:
                          isActive
                              ? Colors.white
                              : accentColor.withOpacity(0.8),
                      fontSize: buttonSize * 0.12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 360;
    final cardPadding = screenSize.width * 0.05;
    final circleSize = screenSize.width * 0.45;

    return Scaffold(
      backgroundColor: secondaryColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              secondaryColor, // Light cream
              primaryColor.withOpacity(0.2), // Coral pink with opacity
              accentColor.withOpacity(0.1), // Deep orange with opacity
            ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // Custom App Bar - With User Info and Logout
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                floating: true,
                snap: true,
                automaticallyImplyLeading: false, // Remove back button
                centerTitle: true,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/gluver_licon.png',
                      height: 28,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "GLUVER",
                      style: TextStyle(
                        color: accentColor,
                        fontSize: isSmallScreen ? 20 : 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                actions: [
                  Container(
                    margin: EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accentColor, primaryColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(25),
                        onTap: _openHistoryScreen,
                        child: Container(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.history,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accentColor, primaryColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(25),
                        onTap: _openProfileScreen,
                        child: Container(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, accentColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(25),
                        onTap: _showLogoutDialog,
                        child: Container(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.logout,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Main Content
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: cardPadding),
                  child: Column(
                    children: [
                      SizedBox(height: 20),

                      // Main Glucose Display Card
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: isLoading ? 1.0 : _pulseAnimation.value,
                            child: Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(screenSize.width * 0.08),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.9),
                                    Colors.white.withOpacity(0.6),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: primaryColor.withOpacity(0.3),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withOpacity(0.2),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                    offset: Offset(0, 15),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  // Circular Progress with Gradient
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Background Circle
                                      Container(
                                        width: circleSize,
                                        height: circleSize,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: RadialGradient(
                                            colors: [
                                              secondaryColor.withOpacity(0.8),
                                              primaryColor.withOpacity(0.1),
                                            ],
                                          ),
                                          border: Border.all(
                                            color: primaryColor.withOpacity(
                                              0.3,
                                            ),
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: primaryColor.withOpacity(
                                                0.3,
                                              ),
                                              blurRadius: 20,
                                              spreadRadius: 5,
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Progress Indicator
                                      SizedBox(
                                        width: circleSize,
                                        height: circleSize,
                                        child: CircularProgressIndicator(
                                          value:
                                              isLoading
                                                  ? 0
                                                  : (glucoseValue / 300).clamp(
                                                    0.0,
                                                    1.0,
                                                  ),
                                          strokeWidth: 10,
                                          backgroundColor: primaryColor
                                              .withOpacity(0.2),
                                          color: _getStatusColor(glucoseStatus),
                                          strokeCap: StrokeCap.round,
                                        ),
                                      ),
                                      // Center Content
                                      Column(
                                        children: [
                                          AnimatedSwitcher(
                                            duration: Duration(
                                              milliseconds: 500,
                                            ),
                                            child: Text(
                                              isLoading
                                                  ? "--"
                                                  : "${glucoseValue.toInt()}",
                                              key: ValueKey(glucoseValue),
                                              style: TextStyle(
                                                fontSize: circleSize * 0.25,
                                                fontWeight: FontWeight.w800,
                                                color: accentColor,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            "mg/dL",
                                            style: TextStyle(
                                              fontSize: circleSize * 0.08,
                                              color: accentColor.withOpacity(
                                                0.8,
                                              ),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),

                                  SizedBox(height: 25),

                                  // Enhanced Status Badge
                                  AnimatedContainer(
                                    duration: Duration(milliseconds: 300),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          _getStatusColor(
                                            glucoseStatus,
                                          ).withOpacity(0.2),
                                          _getStatusColor(
                                            glucoseStatus,
                                          ).withOpacity(0.1),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(25),
                                      border: Border.all(
                                        color: _getStatusColor(glucoseStatus),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _getStatusColor(
                                            glucoseStatus,
                                          ).withOpacity(0.3),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(
                                              glucoseStatus,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          glucoseStatus.toUpperCase(),
                                          style: TextStyle(
                                            color: _getStatusColor(
                                              glucoseStatus,
                                            ),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      SizedBox(height: 40),

                      // Status Section
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.9),
                              Colors.white.withOpacity(0.6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: primaryColor.withOpacity(0.3),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withOpacity(0.2),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              "STATUS KONEKSI",
                              style: TextStyle(
                                fontSize: 12,
                                color: accentColor.withOpacity(0.8),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Color(0xFF4CAF50),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(
                                          0xFF4CAF50,
                                        ).withOpacity(0.5),
                                        blurRadius: 8,
                                        spreadRadius: 3,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  "TERHUBUNG",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF4CAF50),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 30),

                      _buildRecentHistoryCard(),

                      SizedBox(height: 30),

                      // Recommendation Buttons
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.9),
                              Colors.white.withOpacity(0.6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: primaryColor.withOpacity(0.3),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withOpacity(0.2),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              "REKOMENDASI KESEHATAN",
                              style: TextStyle(
                                fontSize: 12,
                                color: accentColor.withOpacity(0.8),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                            SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildRecommendationButton(
                                  "Rendah",
                                  Icons.trending_down,
                                ),
                                _buildRecommendationButton(
                                  "Normal",
                                  Icons.favorite,
                                ),
                                _buildRecommendationButton(
                                  "Cukup Tinggi",
                                  Icons.trending_up,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 30),

                      // Enhanced Refresh Button
                      AnimatedBuilder(
                        animation: _rotationAnimation,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: _rotationAnimation.value * 2 * 3.14159,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [primaryColor, accentColor],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withOpacity(0.6),
                                    blurRadius: 25,
                                    spreadRadius: 5,
                                    offset: Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(40),
                                  onTap: () {
                                    _rotationController.forward().then((_) {
                                      _rotationController.reset();
                                    });
                                    setState(() {
                                      isLoading = true;
                                    });
                                    _listenToGlucoseData();
                                    _loadRecentHistory();
                                  },
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    child: Icon(
                                      Icons.refresh,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      SizedBox(height: 30),
                    ],
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
