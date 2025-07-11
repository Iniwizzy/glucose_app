import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Konfigurasi Firebase - Ganti dengan konfigurasi project Anda
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: 'AIzaSyD3PSR4uMBw2-TeFaoFGUVGYWBwZBDMMXc',
      appId: '1:985617598644:android:e0cebebcaacbff6072afe1',
      messagingSenderId: '985617598644',
      projectId: 'tubes-iot-1bb8c',
      databaseURL: 'https://tubes-iot-1bb8c-default-rtdb.firebaseio.com',
      storageBucket: 'tubes-iot-1bb8c.firebasestorage.app',
    ),
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glucose Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: GlucoseMonitorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GlucoseMonitorScreen extends StatefulWidget {
  @override
  _GlucoseMonitorScreenState createState() => _GlucoseMonitorScreenState();
}

class _GlucoseMonitorScreenState extends State<GlucoseMonitorScreen>
    with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  double glucoseValue = 0.0;
  String glucoseStatus = "Normal";
  bool isLoading = true;

  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;

  // Color palette
  static const Color primaryColor = Color(0xFFF46666); // Coral pink
  static const Color secondaryColor = Color(0xFFFFD6D6); // Light cream
  static const Color accentColor = Color(0xFFCB3305); // Deep orange

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _listenToGlucoseData();
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
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  void _listenToGlucoseData() {
    _database
        .child('glucose_predict/prediction')
        .onValue
        .listen((event) {
          if (event.snapshot.exists) {
            setState(() {
              glucoseValue = double.parse(event.snapshot.value.toString());
              glucoseStatus = _getGlucoseStatus(glucoseValue);
              isLoading = false;
            });
          }
        })
        .onError((error) {
          print("Error listening to Firebase: $error");
          setState(() {
            isLoading = false;
          });
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
              // Custom App Bar - Centered Title Only
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                floating: true,
                snap: true,
                automaticallyImplyLeading: false, // Remove back button
                centerTitle: true,
                title: Text(
                  "Glucose Monitor",
                  style: TextStyle(
                    color: accentColor,
                    fontSize: isSmallScreen ? 20 : 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
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
