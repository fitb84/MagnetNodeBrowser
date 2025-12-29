import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/notification_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/bandwidth_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/ingest_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/browser_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MagnetNode',
      theme: AppTheme.darkTheme(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;


  final List<Widget> _screens = [
    const DashboardScreen(),
    const BandwidthScreen(),
    const DownloadsScreen(),
    const IngestScreen(),
    const SettingsScreen(),
    const BrowserScreen(),
  ];

  final List<String> _titles = [
    'Dashboard',
    'Bandwidth',
    'Downloads',
    'Ingest',
    'Settings',
    'Browser',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFff3b3b),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.lightbulb, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(_titles[_selectedIndex]),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.speed),
            label: 'Bandwidth',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cloud_download),
            label: 'Downloads',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_link),
            label: 'Ingest',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.web),
            label: 'Browser',
          ),
        ],
        onTap: (index) {
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }
}
