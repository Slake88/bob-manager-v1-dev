import 'package:flutter/material.dart';

import '../repositories/member_photo_repository.dart';

class MemberPhotoAvatar extends StatefulWidget {
  const MemberPhotoAvatar({
    super.key,
    required this.member,
    required this.repository,
    this.radius = 22,
    this.thumbnail = true,
  });

  final Map<String, dynamic> member;
  final MemberPhotoRepository repository;
  final double radius;
  final bool thumbnail;

  @override
  State<MemberPhotoAvatar> createState() => _MemberPhotoAvatarState();
}

class _MemberPhotoAvatarState extends State<MemberPhotoAvatar> {
  late Future<String?> _url;

  @override
  void initState() {
    super.initState();
    _url = _loadUrl();
  }

  @override
  void didUpdateWidget(covariant MemberPhotoAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member['photo_path'] != widget.member['photo_path'] ||
        oldWidget.member['id'] != widget.member['id'] ||
        oldWidget.thumbnail != widget.thumbnail) {
      _url = _loadUrl();
    }
  }

  Future<String?> _loadUrl() async {
    try {
      return await widget.repository.signedMemberPhotoUrl(
        widget.member['photo_path'],
        thumbnail: widget.thumbnail,
      );
    } catch (_) {
      return null;
    }
  }

  String get _initial {
    final name = widget.member['full_name']?.toString().trim() ?? '';
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  Widget _fallback() {
    return CircleAvatar(
      radius: widget.radius,
      child: Text(
        _initial,
        style: TextStyle(fontSize: widget.radius * 0.68),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) return _fallback();
        final size = widget.radius * 2;
        return SizedBox(
          width: size,
          height: size,
          child: ClipOval(
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(),
            ),
          ),
        );
      },
    );
  }
}
