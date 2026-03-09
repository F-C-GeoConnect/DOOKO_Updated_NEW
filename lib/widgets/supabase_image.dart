import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SupabaseImage extends StatefulWidget {
  final String imagePath;
  final double? height;
  final double? width;
  final BoxFit fit;
  final String bucket;

  const SupabaseImage({
    super.key,
    required this.imagePath,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.bucket = 'product_images',
  });

  @override
  State<SupabaseImage> createState() => _SupabaseImageState();
}

class _SupabaseImageState extends State<SupabaseImage> {
  Future<String>? _urlFuture;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  void _loadUrl() {
    if (widget.imagePath.isEmpty) {
      _urlFuture = Future.error('Empty path');
      return;
    }

    if (widget.imagePath.startsWith('http')) {
      _urlFuture = Future.value(widget.imagePath);
    } else {
      _urlFuture = Supabase.instance.client.storage
          .from(widget.bucket)
          .createSignedUrl(widget.imagePath, 3600);
    }
  }

  @override
  void didUpdateWidget(SupabaseImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath || oldWidget.bucket != widget.bucket) {
      _loadUrl();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: widget.height,
            width: widget.width,
            color: Colors.grey[200],
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            height: widget.height,
            width: widget.width,
            color: Colors.grey[100],
            child: const Icon(Icons.image_not_supported, color: Colors.grey),
          );
        }
        
        // Use CachedNetworkImage for better performance and lower egress
        return CachedNetworkImage(
          imageUrl: snapshot.data!,
          height: widget.height,
          width: widget.width,
          fit: widget.fit,
          placeholder: (context, url) => Container(
            color: Colors.grey[200],
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (context, url, error) => const Icon(Icons.error),
        );
      },
    );
  }
}
