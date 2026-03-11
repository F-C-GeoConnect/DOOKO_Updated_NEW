import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:untitled1/providers/chat_provider.dart';
import 'package:untitled1/screens/main_screen/my_account.dart';
import 'package:untitled1/services/notification_service.dart';
import 'add_page.dart';
import 'chat_page.dart';
import 'home_page.dart';
import 'listing.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  final _notificationService = NotificationService();

  final List<Widget> _pages = [
    const HomePage(),
    const ListingPage(),
    const AddPage(),
    const ChatPage(),
    const MyAccount(),
  ];

  @override
  void initState() {
    super.initState();
    // Initialize push notifications when user enters main app
    _notificationService.initNotifications();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          final unreadCount = chatProvider.totalUnreadCount;
          
          return BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _selectedIndex,
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor: Colors.grey,
            onTap: _onItemTapped,
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: 'Home',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.list),
                label: 'Listing',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.add),
                label: 'Add',
              ),
              BottomNavigationBarItem(
                icon: Badge(
                  label: unreadCount > 0 ? Text(unreadCount.toString()) : null,
                  isLabelVisible: unreadCount > 0,
                  child: const Icon(Icons.chat_bubble_outline),
                ),
                label: 'Chat',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.account_circle),
                label: 'Account',
              ),
            ],
          );
        },
      ),
    );
  }
}
