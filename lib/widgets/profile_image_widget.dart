import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_application_newtten/utilities/firestore_service.dart';
import 'package:cached_network_image/cached_network_image.dart'; 

class ProfileImageWidget extends StatefulWidget {
  final String username;
  final String? initialImagePath;
  final Function(String path) onImageSelected;

  const ProfileImageWidget({
    super.key, 
    required this.username,
    this.initialImagePath, 
    required this.onImageSelected
  });

  @override
  State<ProfileImageWidget> createState() => _ProfileImageWidgetState();
}

class _ProfileImageWidgetState extends State<ProfileImageWidget> {
  String? _currentImagePath;
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _currentImagePath = widget.initialImagePath;
  }

  @override
  void didUpdateWidget(covariant ProfileImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialImagePath != oldWidget.initialImagePath) {
      setState(() {
        _currentImagePath = widget.initialImagePath;
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 70);
      if (pickedFile != null) {
        setState(() => _isUploading = true);
        File imageFile = File(pickedFile.path);
        String? downloadUrl = await FirestoreService.uploadProfileImage(widget.username, imageFile);

        if (downloadUrl != null) {
          setState(() {
            _currentImagePath = downloadUrl; 
            _isUploading = false; 
          });
          widget.onImageSelected(downloadUrl); 
        } else {
           setState(() => _isUploading = false);
        }
      }
    } catch (e) {
      setState(() => _isUploading = false);
    }
  }

  void _showImagePickerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(leading: const Icon(Icons.photo_library, color: Colors.black), title: const Text('Galeriden Seç'), onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); }),
              ListTile(leading: const Icon(Icons.camera_alt, color: Colors.black), title: const Text('Fotoğraf Çek'), onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;
    
    if (_currentImagePath != null && _currentImagePath!.isNotEmpty) {
      if (_currentImagePath!.startsWith('http')) {
        imageProvider = CachedNetworkImageProvider(_currentImagePath!); 
      } else {
        imageProvider = FileImage(File(_currentImagePath!));
      }
    }

    return GestureDetector(
      onTap: _isUploading ? null : () => _showImagePickerOptions(context),
      // --- 1. HERO EKLENDİ (UÇUŞ KARTI) ---
      // Etiket: 'profile_image_hero'
      // Material widget'ı, uçuş sırasında yazıların altı çizili çıkmasını engeller.
      child: Hero(
        tag: 'profile_image_hero', 
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                ),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: const Color.fromARGB(30, 0, 0, 0),
                  backgroundImage: imageProvider, 
                  child: _isUploading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : (imageProvider == null
                          ? const Icon(Icons.person, size: 50, color: Colors.black)
                          : null),
                ),
              ),
              if (!_isUploading)
                Positioned(
                  bottom: 0,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
