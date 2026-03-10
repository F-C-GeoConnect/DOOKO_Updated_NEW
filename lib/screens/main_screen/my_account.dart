import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../login_screen.dart';
import 'orders_history_screen.dart';
import 'admin_panel.dart';

class MyAccount extends StatefulWidget {
  const MyAccount({super.key});

  @override
  State<MyAccount> createState() => _MyAccountState();
}

class _MyAccountState extends State<MyAccount> {
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  
  bool _isUploading = false;
  bool _isSaving = false;
  
  late final Stream<Map<String, dynamic>?> _profileStream;

  @override
  void initState() {
    super.initState();
    final user = _supabase.auth.currentUser;
    if (user != null) {
      _profileStream = _supabase
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', user.id)
          .map((data) => data.isNotEmpty ? data.first : null);
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await showModalBottomSheet<XFile?>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () async {
                final result = await picker.pickImage(source: ImageSource.camera, imageQuality: 40);
                if (mounted) Navigator.pop(context, result);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                final result = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40);
                if (mounted) Navigator.pop(context, result);
              },
            ),
          ],
        ),
      ),
    );

    if (image == null) return;

    setState(() => _isUploading = true);

    try {
      final user = _supabase.auth.currentUser;
      final file = File(image.path);
      final fileExt = image.path.split('.').last;
      final filePath = '${user!.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await _supabase.storage.from('avatars').upload(filePath, file);
      final imageUrl = _supabase.storage.from('avatars').getPublicUrl(filePath);

      await _supabase.from('profiles').update({'avatar_url': imageUrl}).eq('id', user.id);
      await _supabase.auth.updateUser(UserAttributes(data: {'avatar_url': imageUrl}));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _updateProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      final updates = {
        'full_name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
      };

      await _supabase.from('profiles').update(updates).eq('id', user.id);
      
      await _supabase.auth.updateUser(UserAttributes(
        data: {'full_name': _nameController.text.trim()}
      ));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      debugPrint('Update error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _profileStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.green)));
        }
        
        final profile = snapshot.data;
        if (profile == null) return const Scaffold(body: Center(child: Text('Profile not found')));
        
        final bool isAdmin = profile['is_admin'] ?? false;
        final String phone = profile['phone'] ?? 'Not set';
        final String address = profile['address'] ?? 'Not set';

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            title: const Text('Profile'),
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            titleTextStyle: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          body: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 55,
                              backgroundColor: Colors.green.shade50,
                              backgroundImage: (profile['avatar_url'] != null && profile['avatar_url'].toString().isNotEmpty)
                                  ? CachedNetworkImageProvider(profile['avatar_url'])
                                  : null,
                              child: (profile['avatar_url'] == null || profile['avatar_url'].toString().isEmpty)
                                ? Text((profile['full_name'] ?? 'U')[0].toUpperCase(), style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.green.shade800))
                                : null,
                            ),
                            if (_isUploading)
                              const Positioned.fill(child: CircularProgressIndicator(color: Colors.green)),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _pickAndUploadImage,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(profile['full_name'] ?? 'No Name', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        Text(_supabase.auth.currentUser?.email ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                      ],
                    ),
                  ),
                ),
                _buildStatsSection(),
                
                _buildSectionHeader('CONTACT INFORMATION'),
                _buildInfoCard(
                  items: [
                    _InfoItem(icon: Icons.phone_outlined, label: 'Phone', value: phone),
                    _InfoItem(icon: Icons.location_on_outlined, label: 'Address', value: address),
                  ],
                ),

                if (isAdmin) ...[
                  _buildSectionHeader('ADMINISTRATION'),
                  _buildSettingsItem(
                    icon: Icons.admin_panel_settings,
                    title: 'Admin Dashboard',
                    subtitle: 'Manage products and users',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPanel())),
                  ),
                ],
                
                _buildSectionHeader('ACCOUNT SETTINGS'),
                _buildSettingsItem(
                  icon: Icons.person_outline,
                  title: 'Edit Personal Info',
                  subtitle: 'Update name, phone, and address',
                  onTap: () {
                    _nameController.text = profile['full_name'] ?? '';
                    _phoneController.text = profile['phone'] ?? '';
                    _addressController.text = profile['address'] ?? '';
                    _showEditDialog();
                  },
                ),
                _buildSettingsItem(
                  icon: Icons.history,
                  title: 'My Orders & Activity',
                  subtitle: 'Purchase and sales history',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OrdersHistoryScreen())),
                ),
                _buildSectionHeader('SUPPORT'),
                _buildSettingsItem(icon: Icons.help_outline, title: 'Help Center', onTap: () {}),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildActionButton(text: 'Logout', icon: Icons.logout, color: Colors.red, onTap: _logout),
                ),
                const SizedBox(height: 32),
                Text('App Version 1.0.5', style: TextStyle(color: Colors.grey[400], fontSize: 10)),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard({required List<_InfoItem> items}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return Column(
            children: [
              ListTile(
                leading: Icon(item.icon, color: Colors.green, size: 22),
                title: Text(item.label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                subtitle: Text(item.value, style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500)),
                dense: true,
              ),
              if (index < items.length - 1) const Divider(height: 1, indent: 55),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatsSection() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          FutureBuilder<int>(
            future: _supabase.from('orders').count().eq('seller_id', userId).eq('status', 'completed'),
            builder: (context, snapshot) => _buildStatCard('Units Sold', snapshot.data?.toString() ?? '0', Icons.sell_outlined),
          ),
          const SizedBox(width: 12),
          FutureBuilder<int>(
            future: _supabase.from('orders').count().eq('buyer_id', userId).eq('status', 'completed'),
            builder: (context, snapshot) => _buildStatCard('Bought', snapshot.data?.toString() ?? '0', Icons.shopping_basket_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          children: [
            Icon(icon, color: Colors.green, size: 24),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 8), child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 1)));
  }

  Widget _buildSettingsItem({required IconData icon, required String title, String? subtitle, required VoidCallback onTap}) {
    return Container(
      color: Colors.white,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Colors.black87),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])) : null,
        trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
      ),
    );
  }

  Widget _buildActionButton({required String text, required IconData icon, required Color color, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity, height: 54,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: 20),
        label: Text(text, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(side: BorderSide(color: color.withValues(alpha: 0.5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    );
  }

  void _showEditDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Edit Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name', 
                      prefixIcon: const Icon(Icons.person_outline), 
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number', 
                      prefixIcon: const Icon(Icons.phone_outlined), 
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Default Address', 
                      prefixIcon: const Icon(Icons.location_on_outlined), 
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : () async {
                        setModalState(() => _isSaving = true);
                        await _updateProfile();
                        if (mounted) setModalState(() => _isSaving = false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green, 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isSaving 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  _InfoItem({required this.icon, required this.label, required this.value});
}
