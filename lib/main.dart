import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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

// --- WIDGET UTAMA ---
class MainPageView extends StatefulWidget {
  const MainPageView({super.key});

  @override
  State<MainPageView> createState() => _MainPageViewState();
}

class _MainPageViewState extends State<MainPageView> {
  final PageController _pageController = PageController(initialPage: 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
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

class _JarvisPageState extends State<JarvisPage> with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true; 

  // --- BLUETOOTH VARS ---
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  
  // --- SWITCH VARS ---
  bool _isDoorOpen = false;
  bool _isLamp1On = false; 
  bool _isLamp2On = false; 

  @override
  void initState() {
    super.initState();
    _checkPermissions();

    // Listener status scanning
    FlutterBluePlus.isScanning.listen((state) {
      if (mounted) setState(() => _isScanning = state);
    });
  }

  Future<void> _checkPermissions() async {
    if (await Permission.location.isDenied) await Permission.location.request();
    // Izin mic dihapus karena fitur suara dibuang
    await [Permission.bluetooth, Permission.bluetoothScan, Permission.bluetoothConnect].request();
  }

  // --- FUNGSI EKSEKUSI PERINTAH ---
  // Tipe: 0=Pintu, 1=Lampu1, 2=Lampu2
  void _executeCommand(String bluetoothMsg, bool switchState, int type) {
    _sendMessage(bluetoothMsg);
    
    if (mounted) {
      setState(() {
        if (type == 0) _isDoorOpen = switchState;
        if (type == 1) _isLamp1On = switchState;
        if (type == 2) _isLamp2On = switchState;
      });
      
      // Feedback Getar/Snackbar kecil
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Sending: $bluetoothMsg"), 
          backgroundColor: Colors.cyanAccent.withOpacity(0.8),
          duration: const Duration(milliseconds: 300),
          behavior: SnackBarBehavior.floating,
        )
      );
    }
  }

  // --- BLUETOOTH LOGIC ---
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
      
      // Monitor koneksi putus
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          if (mounted) {
            setState(() { 
              _connectedDevice = null; 
              _writeCharacteristic = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Device Disconnected"), backgroundColor: Colors.red));
          }
        }
      });

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
        title: const Text("JARVIS CONTROLLER", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.cyanAccent)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Icon(
              _connectedDevice != null ? Icons.bluetooth_connected : Icons.bluetooth_disabled, 
              color: _connectedDevice != null ? Colors.cyanAccent : Colors.red
            ),
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
            
            // BAGIAN 1: STATUS DISPLAY (PENGGANTI MIC)
            // Menampilkan ikon besar status koneksi agar tidak kosong
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(
                      color: (_connectedDevice != null ? Colors.cyanAccent : Colors.red).withOpacity(0.1),
                      blurRadius: 50,
                      spreadRadius: 10,
                    )
                  ],
                  border: Border.all(
                    color: (_connectedDevice != null ? Colors.cyanAccent : Colors.red).withOpacity(0.3),
                    width: 2
                  )
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _connectedDevice != null ? Icons.smart_toy_outlined : Icons.bluetooth_searching,
                      size: 80,
                      color: _connectedDevice != null ? Colors.cyanAccent : Colors.redAccent,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _connectedDevice != null ? "SYSTEM ONLINE" : "DISCONNECTED",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                        color: _connectedDevice != null ? Colors.cyanAccent : Colors.redAccent
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_connectedDevice == null)
                      const Text("Please connect to HC-05", style: TextStyle(color: Colors.grey, fontSize: 10)),
                  ],
                ),
              ),
            ),

            // BAGIAN 2: BLUETOOTH LIST (Hanya muncul jika belum connect)
            if (_connectedDevice == null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: _isScanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.search, color: Colors.black),
                  label: Text(_isScanning ? "SCANNING..." : "SCAN DEVICES", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, minimumSize: const Size(double.infinity, 45)),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                flex: 4,
                child: ListView.builder(
                  itemCount: _scanResults.length,
                  itemBuilder: (c, i) {
                    final d = _scanResults[i].device;
                    if (d.platformName.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.white.withOpacity(0.05),
                      ),
                      child: ListTile(
                        title: Text(d.platformName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text(d.remoteId.toString(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        trailing: const Icon(Icons.link, color: Colors.cyanAccent),
                        onTap: () => _connectToDevice(d),
                      ),
                    );
                  },
                ),
              )
            ],

            // BAGIAN 3: SWITCH PANEL (TOMBOL KONTROL)
            // Muncul hanya jika sudah connect
            if (_connectedDevice != null)
              Expanded(
                flex: 5, 
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF151515),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                    boxShadow: [
                      BoxShadow(color: Colors.cyanAccent.withOpacity(0.15), blurRadius: 30, spreadRadius: 1, offset: const Offset(0, -5))
                    ],
                    border: Border(top: BorderSide(color: Colors.cyanAccent.withOpacity(0.3), width: 1)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
                  child: Column(
                    children: [
                      const Text("CONTROL PANEL", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.white54)),
                      const SizedBox(height: 25),
                      
                      // 1. TOMBOL PINTU (Full Width)
                      _buildBigButton("DOOR LOCK", _isDoorOpen, Icons.door_front_door, () {
                        bool newState = !_isDoorOpen;
                        _executeCommand(newState ? "DOOR_OPEN" : "DOOR_CLOSE", newState, 0);
                      }),

                      const SizedBox(height: 20),

                      // 2. TOMBOL LAMPU 1 & 2 (Grid/Row)
                      Expanded(
                        child: Row(
                          children: [
                            // LAMPU 1 (L1)
                            Expanded(
                              child: _buildBigButton("LAMP 1", _isLamp1On, Icons.lightbulb, () {
                                bool newState = !_isLamp1On;
                                _executeCommand(newState ? "L1_ON" : "L1_OFF", newState, 1);
                              }),
                            ),
                            
                            const SizedBox(width: 20), 
                            
                            // LAMPU 2 (L2)
                            Expanded(
                              child: _buildBigButton("LAMP 2", _isLamp2On, Icons.lightbulb_outline, () {
                                bool newState = !_isLamp2On;
                                _executeCommand(newState ? "L2_ON" : "L2_OFF", newState, 2);
                              }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(" GESER UNTUK CREDIT >>", style: TextStyle(fontSize: 10, color: Colors.white24)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Widget Tombol Kotak Besar
  Widget _buildBigButton(String label, bool isActive, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        decoration: BoxDecoration(
          color: isActive ? Colors.cyanAccent.withOpacity(0.2) : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isActive ? Colors.cyanAccent : Colors.white10, 
            width: isActive ? 2 : 1
          ),
          boxShadow: isActive ? [
            BoxShadow(color: Colors.cyanAccent.withOpacity(0.3), blurRadius: 20, spreadRadius: 1)
          ] : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 45, color: isActive ? Colors.white : Colors.grey[700]),
            const SizedBox(height: 15),
            Text(
              label, 
              style: TextStyle(
                fontSize: 16, 
                fontWeight: FontWeight.bold, 
                color: isActive ? Colors.white : Colors.grey
              )
            ),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? Colors.cyanAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(10)
              ),
              child: Text(
                isActive ? "ACTIVE" : "OFF",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.black : Colors.redAccent,
                  letterSpacing: 1
                ),
              ),
            )
          ],
        ),
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
      "2. Afdoluddin",
      "3. Ratna Sari",
      "4. Sania Aulia",
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
            Text("KELOMPOK 5", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.cyanAccent, letterSpacing: 3, shadows: [BoxShadow(color: Colors.cyan.withOpacity(0.8), blurRadius: 10)])),
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