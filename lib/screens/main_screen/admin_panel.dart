import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final _supabase = Supabase.instance.client;
  
  Future<void> _deleteProduct(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Admin Deletion'),
        content: Text('Are you sure you want to delete product "$name"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('products').delete().eq('id', id);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product removed by admin.')));
        setState(() {}); 
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _toggleBanUser(String userId, String name, bool currentBanStatus) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (userId == currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You cannot ban yourself!'), backgroundColor: Colors.orange));
      return;
    }

    final action = currentBanStatus ? 'Unban' : 'Ban';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action User'),
        content: Text('Are you sure you want to $action "$name"?\n\n' + 
          (currentBanStatus 
            ? 'They will regain access to the app.' 
            : 'They will be blocked from using the app with this email account.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: Text(action, style: TextStyle(color: currentBanStatus ? Colors.green : Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('profiles').update({'is_banned': !currentBanStatus}).eq('id', userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User ${currentBanStatus ? "unbanned" : "banned"} successfully.'))
          );
        }
        setState(() {}); 
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _toggleVerifyUser(String userId, String name, bool currentVerifyStatus) async {
    final action = currentVerifyStatus ? 'Unverify' : 'Verify';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action User'),
        content: Text('Are you sure you want to $action "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: Text(action, style: TextStyle(color: currentVerifyStatus ? Colors.orange : Colors.blue))
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('profiles').update({'is_verified': !currentVerifyStatus}).eq('id', userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User ${currentVerifyStatus ? "unverified" : "verified"} successfully.'))
          );
        }
        setState(() {}); 
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Control Panel', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              labelColor: Colors.red,
              indicatorColor: Colors.red,
              tabs: [
                Tab(icon: Icon(Icons.inventory), text: 'Products'),
                Tab(icon: Icon(Icons.people), text: 'Users'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildProductsTab(),
                  _buildUsersTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _supabase.from('products').select().order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final products = snapshot.data!;
        if (products.isEmpty) return const Center(child: Text('No products found.'));
        
        return ListView.builder(
          itemCount: products.length,
          itemBuilder: (context, index) {
            final p = products[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: (p['imageUrl'] != null && p['imageUrl'].toString().isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: p['imageUrl'], 
                        width: 40, 
                        height: 40, 
                        fit: BoxFit.cover, 
                        errorWidget: (c,u,e) => const Icon(Icons.image)
                      )
                    : const Icon(Icons.image),
                title: Text(p['productName'] ?? 'No Name'),
                subtitle: Text('Seller: ${p['sellerName']}\nID: ${p['id']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  onPressed: () => _deleteProduct(p['id'], p['productName'] ?? ''),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUsersTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _supabase.from('profiles').select().order('full_name'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final users = snapshot.data!;
        if (users.isEmpty) return const Center(child: Text('No users found.'));
        
        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final u = users[index];
            final bool isAdmin = u['is_admin'] ?? false;
            final bool isBanned = u['is_banned'] ?? false;
            final bool isVerified = u['is_verified'] ?? false;
            final String userId = u['id'];
            final String userName = u['full_name'] ?? 'No Name';

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: (u['avatar_url'] != null && u['avatar_url'].toString().isNotEmpty) 
                    ? CachedNetworkImageProvider(u['avatar_url']) 
                    : null,
                child: (u['avatar_url'] == null || u['avatar_url'].toString().isEmpty) 
                    ? Text(userName[0].toUpperCase()) 
                    : null,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(userName, style: TextStyle(
                      decoration: isBanned ? TextDecoration.lineThrough : null,
                      color: isBanned ? Colors.grey : Colors.black,
                    )),
                  ),
                  if (isVerified) const Icon(Icons.verified, color: Colors.green, size: 16),
                ],
              ),
              subtitle: Text(isAdmin ? 'Administrator' : (isBanned ? 'BANNED' : 'User')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      isVerified ? Icons.verified : Icons.verified_outlined, 
                      color: isVerified ? Colors.green : Colors.grey, 
                      size: 20
                    ),
                    tooltip: isVerified ? 'Unverify User' : 'Verify User',
                    onPressed: () => _toggleVerifyUser(userId, userName, isVerified),
                  ),
                  IconButton(
                    icon: Icon(
                      isBanned ? Icons.gavel : Icons.block, 
                      color: isBanned ? Colors.green : Colors.redAccent, 
                      size: 20
                    ),
                    tooltip: isBanned ? 'Unban User' : 'Ban User',
                    onPressed: () => _toggleBanUser(userId, userName, isBanned),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
