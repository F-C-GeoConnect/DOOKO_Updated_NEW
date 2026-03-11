import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/product_service.dart';

class AddPage extends StatefulWidget {
  const AddPage({super.key});

  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  final _productService = ProductService();
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _totalQuantityController = TextEditingController();

  File? _imageFile;
  bool _isUploading = false;
  String _selectedUnit = 'per kg';
  String? _selectedCategory;

  final List<String> _categories = [
    'Vegetables',
    'Fruits',
    'Dairy',
    'Grains',
    'Meat & Fish',
    'Honey',
    'Others'
  ];

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 40,
    );

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
    // FIXED: Explicitly check if _selectedCategory is null before proceeding
    if (!_formKey.currentState!.validate() || _imageFile == null || _selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields, select a category, and add an image.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final Position position = await _determinePosition();
      
      final imageUrl = await _productService.uploadProductImage(_imageFile!);

      final locationString = 'POINT(${position.longitude} ${position.latitude})';

      // Use the local _selectedCategory state variable
      await _productService.postProduct(
        name: _nameController.text.trim(),
        price: double.tryParse(_priceController.text) ?? 0.0,
        description: _descriptionController.text.trim(),
        imageUrl: imageUrl,
        category: _selectedCategory!, // Passing the selected category
        unit: _selectedUnit,
        totalQuantity: double.tryParse(_totalQuantityController.text) ?? 0.0,
        locationString: locationString,
      );

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
      _selectedCategory = null; // Reset category selection
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _totalQuantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Post New Product', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImagePicker(colorScheme),
              const SizedBox(height: 24),
              _buildTextField(
                controller: _nameController, 
                label: 'Product Name', 
                icon: Icons.shopping_bag_outlined,
              ),
              const SizedBox(height: 16),
              _buildCategoryDropdown(colorScheme),
              const SizedBox(height: 24),
              const Text('Pricing & Availability', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildUnitAndPriceSection(colorScheme),
              const SizedBox(height: 24),
              _buildTextField(
                controller: _descriptionController, 
                label: 'Product Description', 
                icon: Icons.description_outlined,
                maxLines: 3,
              ),
              const SizedBox(height: 32),
              _isUploading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                onPressed: _postProduct,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Post Product', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePicker(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outline.withOpacity(0.5), width: 1),
        ),
        child: _imageFile != null
            ? ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(_imageFile!, fit: BoxFit.cover),
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_rounded, color: colorScheme.primary, size: 48),
            const SizedBox(height: 12),
            Text('Take a product photo', 
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('Only camera photos are allowed', 
              style: TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.6), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller, 
    required String label, 
    required IconData icon,
    int maxLines = 1
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        alignLabelWithHint: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      validator: (value) => value!.trim().isEmpty ? '$label is required' : null,
    );
  }

  Widget _buildCategoryDropdown(ColorScheme colorScheme) {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      decoration: InputDecoration(
        labelText: 'Category',
        prefixIcon: const Icon(Icons.category_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      items: _categories
          .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedCategory = value;
        });
      },
      validator: (value) => value == null ? 'Please select a category' : null,
    );
  }

  Widget _buildUnitAndPriceSection(ColorScheme colorScheme) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _priceController,
                decoration: InputDecoration(
                  labelText: 'Price',
                  prefixText: 'Rs. ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                keyboardType: TextInputType.number,
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: _selectedUnit,
                decoration: InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                items: ['per kg', 'per liter', 'per piece']
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedUnit = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _totalQuantityController,
          decoration: InputDecoration(
            labelText: 'Total Quantity Available',
            hintText: 'e.g. 50',
            suffixText: _selectedUnit.replaceAll('per ', ''),
            prefixIcon: const Icon(Icons.inventory_2_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          keyboardType: TextInputType.number,
          validator: (value) => value!.isEmpty ? 'Required' : null,
        ),
      ],
    );
  }
}
