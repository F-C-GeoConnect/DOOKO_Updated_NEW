import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddPage extends StatefulWidget {
  const AddPage({super.key});

  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _totalQuantityController = TextEditingController();

  File? _imageFile;
  bool _isUploading = false;
  String _selectedUnit = 'per kg';

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }
    return await Geolocator.getCurrentPosition();
  }

  Future<void> _postProduct() async {
    if (!_formKey.currentState!.validate() || _imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and add an image.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw const AuthException('User not authenticated. Please log in again.');
      }

      final Position position = await _determinePosition();
      final imageFile = _imageFile!;
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.${imageFile.path.split('.').last}';

      // 1. Upload the file
      await supabase.storage.from('product_images').upload(fileName, imageFile);
      
      // 2. ONLY store the filename/path in the database, NOT the full URL
      final String imagePath = fileName;

      final locationString = 'POINT(${position.longitude} ${position.latitude})';

      await supabase.from('products').insert({
        'productName': _nameController.text,
        'price': double.tryParse(_priceController.text) ?? 0.0,
        'description': _descriptionController.text,
        'imageUrl': imagePath, // Storing "photo.jpg"
        'sellerName': user.userMetadata?['full_name'] ?? 'Anonymous Seller',
        'sellerID': user.id,
        'seller_id': user.id,
        'location': locationString,
        'unit': _selectedUnit,
        'total_quantity': double.tryParse(_totalQuantityController.text) ?? 0.0,
        'quantity': int.tryParse(_totalQuantityController.text) ?? 0,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product posted successfully!')),
        );
        _clearForm();
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post product: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _clearForm() {
    _nameController.clear();
    _priceController.clear();
    _descriptionController.clear();
    _totalQuantityController.clear();
    setState(() {
      _imageFile = null;
      _selectedUnit = 'per kg';
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.clear();
    _descriptionController.dispose();
    _totalQuantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Product Detail'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImagePicker(),
              const SizedBox(height: 24),
              _buildTextField(_nameController, 'Product Name'),
              const SizedBox(height: 24),
              _buildUnitAndPriceSection(),
              const SizedBox(height: 16),
              _buildTextField(_descriptionController, 'Product Detail', maxLines: 3),
              const SizedBox(height: 32),
              _isUploading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                onPressed: _postProduct,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Post Product', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: _imageFile != null
            ? ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(_imageFile!, fit: BoxFit.cover),
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt_outlined, color: Colors.grey[600], size: 40),
            const SizedBox(height: 8),
            const Text('Take a photo', style: TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      validator: (value) => value!.isEmpty ? '$label can\'t be empty' : null,
    );
  }

  Widget _buildUnitAndPriceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pricing & Quantity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _priceController,
                decoration: InputDecoration(
                  labelText: 'Price',
                  prefixText: 'Rs. ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.number,
                validator: (value) => value!.isEmpty ? 'Price is required' : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                value: _selectedUnit,
                decoration: InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: ['per kg', 'per liter', 'per piece']
                    .map((label) => DropdownMenuItem(child: Text(label), value: label))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedUnit = value;
                    });
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _totalQuantityController,
          decoration: InputDecoration(
            labelText: 'Total Quantity Available',
            suffixText: _selectedUnit.replaceAll('per ', ''),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          keyboardType: TextInputType.number,
          validator: (value) => value!.isEmpty ? 'Total quantity is required' : null,
        ),
      ],
    );
  }
}
