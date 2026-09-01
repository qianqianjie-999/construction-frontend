import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class PhotoPickerWidget extends StatefulWidget {
  final List<dynamic> photos; // File (mobile) or XFile (web)
  final Function(List<dynamic>) onPhotosChanged;
  final String label;

  const PhotoPickerWidget({
    super.key,
    required this.photos,
    required this.onPhotosChanged,
    required this.label,
  });

  @override
  State<PhotoPickerWidget> createState() => _PhotoPickerWidgetState();
}

class _PhotoPickerWidgetState extends State<PhotoPickerWidget> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (photo != null) {
        final photos = List<dynamic>.from(widget.photos)..add(photo);
        widget.onPhotosChanged(photos);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('拍照失败：$e', style: const TextStyle(color: Color(0xFFf1f5f9))),
          backgroundColor: const Color(0xFF1a2332),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _showPhotoSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a2332),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF00d4ff)),
              title: const Text('拍照', style: TextStyle(color: Color(0xFFf1f5f9))),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF00d4ff)),
              title: const Text('从相册选择', style: TextStyle(color: Color(0xFFf1f5f9))),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _removePhoto(int index) {
    final photos = List<dynamic>.from(widget.photos)..removeAt(index);
    widget.onPhotosChanged(photos);
  }

  Widget _buildImage(dynamic photo, double width, double height) {
    if (kIsWeb) {
      // Web: XFile -> read bytes
      final xFile = photo as XFile;
      return FutureBuilder<Uint8List>(
        future: xFile.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              width: width,
              height: height,
              color: const Color(0xFF111827),
              child: const Icon(Icons.image, color: Color(0xFF64748b)),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Container(
              width: width,
              height: height,
              color: const Color(0xFF111827),
              child: const Icon(Icons.error, color: Color(0xFFef4444)),
            );
          }
          return Image.memory(
            snapshot.data!,
            width: width,
            height: height,
            fit: BoxFit.cover,
          );
        },
      );
    } else {
      // Mobile: File
      return Image.file(
        photo as File,
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    }
  }

  void _previewPhoto(dynamic photo) {
    if (kIsWeb) {
      final xFile = photo as XFile;
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: FutureBuilder<Uint8List>(
            future: xFile.readAsBytes(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return InteractiveViewer(
                  child: Image.memory(snapshot.data!),
                );
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: InteractiveViewer(
            child: Image.file(photo as File),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.photos.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.photos.asMap().entries.map((entry) {
              final index = entry.key;
              final photo = entry.value;
              return Stack(
                children: [
                  GestureDetector(
                    onTap: () => _previewPhoto(photo),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildImage(photo, 80, 80),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => _removePhoto(index),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _showPhotoSourceDialog,
          icon: const Icon(Icons.add_photo_alternate, color: Color(0xFF00d4ff)),
          label: Text(widget.label, style: const TextStyle(color: Color(0xFF00d4ff))),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFF00d4ff)),
          ).copyWith(
            shape: MaterialStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
        ),
      ],
    );
  }
}
