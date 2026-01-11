import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: "Jarvis Controller",
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF050505),
      primaryColor: Colors.cyanAccent,
      colorScheme: const ColorScheme.dark(
        primary: Colors.cyanAccent,
        secondary: Colors.blueAccent,
      ),
    ),
    home: const MainPageView(),
  ));
}

// --- WIDGET UTAMA (PAGE VIEW UNTUK SLIDE) ---
class MainPageView extends StatefulWidget {
  const MainPageView({super.key});

  @override
  State<MainPageView> createState() => _MainPageViewState();
}

class _MainPageViewState extends State<MainPageView> {
  // --- INI BARIS YANG HILANG SEBELUMNYA ---
  final PageController _pageController = PageController(initialPage: 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController, // Menggunakan controller di sini
        children: const [
          JarvisPage(),   // Halaman 1: Kontrol
          CreditsPage(),  // Halaman 2: Credit
        ],
      ),
    );
  }
}

// --- HALAMAN KONTROLER JARVIS ---
class JarvisPage extends StatefulWidget {
  const JarvisPage({super.key});

  @override
  State<JarvisPage> createState() => _JarvisPageState();
}

class _JarvisPageState extends State<JarvisPage> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true; // Agar Bluetooth tidak putus saat slide

  // --- BLUETOOTH VARS ---
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;

  // --- VOICE VARS ---
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _textSpoken = "Tekan Mic & Bicara...";
  
  // --- ANIMASI UI ---
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  // --- SWITCH VARS ---
  bool _isDoorOpen = false;
  bool _isLampOn = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _checkPermissions();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 5.0, end: 20.0).animate(_glowController);

    FlutterBluePlus.isScanning.listen((state) {
      if (mounted) setState(() => _isScanning = state);
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    if (await Permission.location.isDenied) await Permission.location.request();
    if (await Permission.microphone.isDenied) await Permission.microphone.request();
    await [Permission.bluetooth, Permission.bluetoothScan, Permission.bluetoothConnect].request();
  }

  // ==========================================================
  // LOGIKA SUARA (ANTI STUCK + IF ELSE STYLE)
  // ==========================================================
  void _listen() async {
    if (!_isListening) {
      try {
        // --- TAMBAHKAN TRY-CATCH DI SINI ---
        bool available = await _speech.initialize(
          onStatus: (val) {
            if (val == 'done' || val == 'notListening') {
               if(mounted) setState(() => _isListening = false);
            }
          },
          onError: (val) {
            print('Error Speech: ${val.errorMsg}');
            if(mounted) setState(() => _isListening = false);
          },
          debugLogging: true, // Biar error jelas terlihat di console
        );

        if (available) {
          setState(() {
            _isListening = true;
            _textSpoken = "Mendengarkan...";
          });
          
          _speech.listen(
            localeId: "id_ID",
            listenFor: const Duration(seconds: 10),
            pauseFor: const Duration(seconds: 3),
            onResult: (val) {
              setState(() {
                _textSpoken = val.recognizedWords;
                if (val.finalResult) {
                  _processCommand(val.recognizedWords);
                }
              });
            },
          );
        } else {
          // Jika HP menolak (available = false)
          setState(() => _textSpoken = "Mic ditolak oleh HP");
          print("User denied the use of speech recognition.");
        }
      } catch (e) {
        // --- TANGKAP ERROR AGAR TIDAK CRASH ---
        print("CRITICAL ERROR: $e");
        setState(() {
          _isListening = false;
          _textSpoken = "Gagal Init: Cek Google App";
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Error: Pastikan Google App terinstall & Default Assistant aktif"),
            backgroundColor: Colors.red,
          )
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }
  void _processCommand(String command) {
    String cmd = command.toLowerCase(); 

    // --- LOGIKA IF ELSE (GAYA LAMA) ---
    if (cmd.contains("nyalakan lampu") || cmd.contains("hidupkan lampu")) { 
      _executeCommand("LAMP_ON", true); 
    } 
    else if (cmd.contains("matikan lampu")) { 
      _executeCommand("LAMP_OFF", false); 
    } 
    else if (cmd.contains("buka pintu")) { 
      _executeCommand("DOOR_OPEN", true); 
    } 
    else if (cmd.contains("tutup pintu")) { 
      _executeCommand("DOOR_CLOSE", false); 
    }
  }

  void _executeCommand(String bluetoothMsg, bool switchState) {
    // 1. Kirim Bluetooth
    _sendMessage(bluetoothMsg);
    
    // 2. Update Switch UI
    setState(() {
      if (bluetoothMsg.contains("DOOR")) _isDoorOpen = switchState;
      if (bluetoothMsg.contains("LAMP")) _isLampOn = switchState;
    });
    
    // 3. Feedback Snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Perintah: $bluetoothMsg"), 
        backgroundColor: Colors.cyanAccent.withOpacity(0.8),
        duration: const Duration(seconds: 1),
      )
    );
  }
  // ==========================================================

  Future<void> _startScan() async {
    setState(() => _scanResults = []);
    try { await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5)); } catch (e) { print(e); }
    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) setState(() => _scanResults = results);
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();
      await device.connect(autoConnect: false);
      setState(() => _connectedDevice = device);
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var c in service.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            setState(() => _writeCharacteristic = c);
          }
        }
      }
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Connected: ${device.platformName}")));
    } catch (e) { print(e); }
  }

  Future<void> _sendMessage(String text) async {
    if (_writeCharacteristic == null) return;
    try { await _writeCharacteristic!.write(utf8.encode(text)); } catch (e) { print(e); }
  }

  // --- UI TAMPILAN ---
  @override
  Widget build(BuildContext context) {
    super.build(context); 

    return Scaffold(
      appBar: AppBar(
        title: const Text("JARVIS SYSTEM", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.cyanAccent)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Icon(Icons.bluetooth, color: _connectedDevice != null ? Colors.cyanAccent : Colors.red),
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Color(0xFF101010)],
          ),
        ),
        child: Column(
          children: [
            // BAGIAN 1: TEKS & MIC
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // --- TEKS REALTIME DI ATAS MIC ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      _textSpoken, 
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22, 
                        fontWeight: FontWeight.bold,
                        color: _isListening ? Colors.cyanAccent : Colors.white54,
                        shadows: _isListening ? [const BoxShadow(color: Colors.cyan, blurRadius: 10)] : [],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  // --- TOMBOL MIC ---
                  GestureDetector(
                    onTapDown: (_) => _listen(),
                    child: AnimatedBuilder(
                      animation: _glowAnimation,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isListening ? Colors.red : Colors.cyanAccent).withOpacity(0.6),
                                blurRadius: _isListening ? 50 : _glowAnimation.value,
                                spreadRadius: _isListening ? 10 : _glowAnimation.value / 2,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.black,
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              size: 40,
                              color: _isListening ? Colors.redAccent : Colors.cyanAccent,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("<< GESER UNTUK CREDIT >>", style: TextStyle(fontSize: 10, color: Colors.white24)),
                ],
              ),
            ),

            // BAGIAN 2: BLUETOOTH LIST
            if (_connectedDevice == null) ...[
              const Divider(color: Colors.white24),
              ElevatedButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: _isScanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.search, color: Colors.black),
                label: Text(_isScanning ? "SCANNING..." : "SCAN DEVICES", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
              ),
              Expanded(
                flex: 3,
                child: ListView.builder(
                  itemCount: _scanResults.length,
                  itemBuilder: (c, i) {
                    final d = _scanResults[i].device;
                    if (d.platformName.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.white.withOpacity(0.05),
                      ),
                      child: ListTile(
                        title: Text(d.platformName, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(d.remoteId.toString(), style: const TextStyle(color: Colors.grey)),
                        trailing: TextButton(
                          onPressed: () => _connectToDevice(d),
                          child: const Text("CONNECT", style: TextStyle(color: Colors.cyanAccent)),
                        ),
                      ),
                    );
                  },
                ),
              )
            ],

            // BAGIAN 3: SWITCH PANEL
            if (_connectedDevice != null)
              Expanded(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [
                      BoxShadow(color: Colors.cyanAccent.withOpacity(0.2), blurRadius: 20, spreadRadius: 1)
                    ],
                    border: Border(top: BorderSide(color: Colors.cyanAccent.withOpacity(0.5), width: 1)),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text("MANUAL OVERRIDE", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.cyanAccent)),
                      const SizedBox(height: 20),
                      
                      _buildGlowSwitch("DOOR LOCK", _isDoorOpen, Icons.door_front_door, (val) {
                        setState(() => _isDoorOpen = val);
                        _sendMessage(val ? "DOOR_OPEN" : "DOOR_CLOSE");
                      }),
                      
                      const SizedBox(height: 15),

                      _buildGlowSwitch("LIGHT SYSTEM", _isLampOn, Icons.lightbulb, (val) {
                         setState(() => _isLampOn = val);
                        _sendMessage(val ? "LAMP_ON" : "LAMP_OFF");
                      }),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlowSwitch(String label, bool value, IconData icon, Function(bool) onChanged) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: value ? Colors.cyanAccent : Colors.grey, width: 1),
        boxShadow: value ? [BoxShadow(color: Colors.cyanAccent.withOpacity(0.4), blurRadius: 10)] : [],
      ),
      child: SwitchListTile(
        title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        secondary: Icon(icon, color: value ? Colors.cyanAccent : Colors.grey),
        value: value,
        activeColor: Colors.cyanAccent,
        inactiveThumbColor: Colors.grey,
        inactiveTrackColor: Colors.black,
        onChanged: onChanged,
      ),
    );
  }
}

// --- HALAMAN CREDIT ---
class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> members = [
      "1. Bagus Kurniawan",
      "2. Nama Anggota 2",
      "3. Nama Anggota 3",
      "4. Nama Anggota 4",
      "5. Nama Anggota 5",
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Colors.black, Color(0xFF002222)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group_work, size: 80, color: Colors.cyanAccent),
            const SizedBox(height: 20),
            Text("DEVELOPMENT TEAM", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.cyanAccent, letterSpacing: 3, shadows: [BoxShadow(color: Colors.cyan.withOpacity(0.8), blurRadius: 10)])),
            const SizedBox(height: 40),
            ...members.map((name) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                name,
                style: const TextStyle(fontSize: 18, color: Colors.white, letterSpacing: 1),
              ),
            )),
            const SizedBox(height: 50),
            const Text("<< GESER KEMBALI UNTUK KONTROL", style: TextStyle(fontSize: 10, color: Colors.white24)),
          ],
        ),
      ),
    );
  }
}