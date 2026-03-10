import 'package:flutter/material.dart';
import 'package:untitled1/screens/main_screen/main_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;

        if (session != null) {
          // LISTEN to the user profile table in real-time
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: supabase
                .from('profiles')
                .stream(primaryKey: ['id'])
                .eq('id', session.user.id),
            builder: (context, profileSnapshot) {
              // Handle compilation or stream errors
              if (profileSnapshot.hasError) {
                debugPrint('AuthGate Profile Error: ${profileSnapshot.error}');
                return const MainPage(); // Default to app access on error
              }

              // Wait for data
              if (profileSnapshot.connectionState == ConnectionState.waiting && !profileSnapshot.hasData) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              final profile = (profileSnapshot.data != null && profileSnapshot.data!.isNotEmpty) 
                  ? profileSnapshot.data!.first 
                  : null;
                  
              final isBanned = profile?['is_banned'] ?? false;

              if (isBanned) {
                // If banned, sign them out and show message
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  await supabase.auth.signOut();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Your account has been banned. Access denied.'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 5),
                      ),
                    );
                  }
                });
                return const LoginScreen();
              }

              // If not banned, continue to app
              return const MainPage();
            },
          );
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
