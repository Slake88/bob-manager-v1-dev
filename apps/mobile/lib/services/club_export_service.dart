import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_session.dart';
import '../core/club_export.dart';
import '../repositories/club_export_repository.dart';

class ClubExportService {
  ClubExportService({
    ClubExportRepository? repository,
    SupabaseClient? client,
  })  : _repository = repository ?? ClubExportRepository(client: client),
        _clientOverride = client;

  static const int maxArchiveInputBytes = 200 * 1024 * 1024;

  final ClubExportRepository _repository;
  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  Future<ClubExportPackage> generate({
    required Set<ClubExportSection> sections,
    required bool includeSensitive,
    required bool includeFiles,
    void Function(String message)? onProgress,
  }) async {
    if (sections.isEmpty) {
      throw const ClubExportFailure(
        'no_sections',
        'Seleciona pelo menos uma área para exportar.',
      );
    }
    if (!ClubExportPolicy.canExport(AppSession.instance)) {
      throw const ClubExportFailure(
        'permission_denied',
        'Sem permissão para exportação integral.',
      );
    }
    if (includeSensitive &&
        !ClubExportPolicy.canIncludeSensitive(AppSession.instance)) {
      throw const ClubExportFailure(
        'sensitive_permission_denied',
        'Sem permissão para incluir dados altamente sensíveis.',
      );
    }

    onProgress?.call('A registar a exportação...');
    late final String exportId;
    try {
      exportId = await _repository.begin(
        sections: sections,
        includeSensitive: includeSensitive,
        includeFiles: includeFiles,
      );
    } catch (_) {
      throw const ClubExportFailure(
        'export_start_failed',
        'Não foi possível iniciar a exportação integral.',
      );
    }

    try {
      onProgress?.call('A recolher os dados...');
      final bundle = await _repository.loadBundle(
        exportId: exportId,
        sections: sections,
        includeSensitive: includeSensitive,
        includeFiles: includeFiles,
      );

      final knownBytes = bundle.files.fold<int>(
        0,
        (total, file) => total + (file.knownSize ?? 0),
      );
      if (knownBytes > maxArchiveInputBytes) {
        throw const ClubExportFailure(
          'package_too_large',
          'Os ficheiros selecionados ultrapassam o limite de 200 MB.',
        );
      }

      onProgress?.call('A construir o pacote ZIP...');
      final package = await buildPackage(
        exportId: exportId,
        bundle: bundle,
        sections: sections,
        includeSensitive: includeSensitive,
        includeFiles: includeFiles,
        onProgress: onProgress,
      );

      await _repository.complete(
        exportId: exportId,
        datasetCount: package.datasetCount,
        rowCount: package.rowCount,
        fileCount: package.fileCount,
        byteSize: package.bytes.length,
      );
      return package;
    } on ClubExportFailure catch (error) {
      await _safeFail(exportId, error.code);
      rethrow;
    } catch (_) {
      await _safeFail(exportId, 'generation_failed');
      throw const ClubExportFailure(
        'generation_failed',
        'Não foi possível gerar a exportação integral.',
      );
    }
  }

  Future<ClubExportPackage> buildPackage({
    required String exportId,
    required ClubExportBundle bundle,
    required Set<ClubExportSection> sections,
    required bool includeSensitive,
    required bool includeFiles,
    void Function(String message)? onProgress,
  }) async {
    final archive = Archive();
    var inputBytes = 0;
    var fileCount = 0;
    final includedFiles = <Map<String, dynamic>>[];

    for (final dataset in bundle.datasets) {
      final bytes = Uint8List.fromList(datasetCsvBytes(dataset));
      inputBytes += bytes.length;
      _checkLimit(inputBytes);
      archive.addFile(
        ArchiveFile(
          safeArchiveName(dataset.path),
          bytes.length,
          bytes,
        ),
      );
    }

    if (includeFiles) {
      for (var index = 0; index < bundle.files.length; index++) {
        final ref = bundle.files[index];
        onProgress?.call(
          'A incluir ficheiro ${index + 1} de ${bundle.files.length}...',
        );
        Uint8List bytes;
        try {
          bytes = await _client.storage.from(ref.bucket).download(ref.storagePath);
        } catch (_) {
          throw ClubExportFailure(
            'file_download_failed',
            'Não foi possível incluir um dos ficheiros selecionados.',
          );
        }
        inputBytes += bytes.length;
        _checkLimit(inputBytes);
        final path = safeArchiveName(ref.archivePath);
        archive.addFile(ArchiveFile(path, bytes.length, bytes));
        fileCount++;
        includedFiles.add({
          'bucket': ref.bucket,
          'archive_path': path,
          'byte_size': bytes.length,
        });
      }
    }

    final generatedAt = DateTime.now();
    final manifest = <String, dynamic>{
      'format': 'bob-export-v1',
      'generated_at': generatedAt.toUtc().toIso8601String(),
      'export_id': exportId,
      'club': {
        'id': bundle.club['id'],
        'name': bundle.club['name'],
        'legal_name': bundle.club['legal_name'],
        'currency': bundle.club['currency'],
        'timezone': bundle.club['timezone'],
      },
      'sections': sections.map((section) => section.key).toList()..sort(),
      'include_sensitive': includeSensitive,
      'include_files': includeFiles,
      'datasets': bundle.datasets
          .map(
            (dataset) => {
              'path': safeArchiveName(dataset.path),
              'rows': dataset.rowCount,
              'sensitive': dataset.sensitive,
            },
          )
          .toList(),
      'files': includedFiles,
      'totals': {
        'datasets': bundle.datasets.length,
        'rows': bundle.rowCount,
        'files': fileCount,
      },
      'privacy': {
        'audit_payloads_excluded': true,
        'auth_secrets_excluded': true,
        'push_tokens_excluded': true,
        'raw_ocr_payloads_excluded': true,
        'sensitive_data_requires_explicit_option': true,
      },
    };
    final manifestBytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    );
    inputBytes += manifestBytes.length;
    _checkLimit(inputBytes);
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final zip = ZipEncoder().encodeBytes(archive);
    if (zip.isEmpty) {
      throw const ClubExportFailure(
        'zip_failed',
        'Não foi possível criar o pacote ZIP.',
      );
    }
    final filename =
        'BOB_Export_Integral_${DateFormat('yyyyMMdd_HHmm').format(generatedAt)}.zip';
    return ClubExportPackage(
      bytes: zip,
      filename: filename,
      exportId: exportId,
      datasetCount: bundle.datasets.length,
      rowCount: bundle.rowCount,
      fileCount: fileCount,
    );
  }

  Future<void> share(BuildContext context, ClubExportPackage package) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(package.bytes),
            mimeType: 'application/zip',
          ),
        ],
        fileNameOverrides: [package.filename],
        title: 'Exportação integral BOB',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _safeFail(String exportId, String code) async {
    try {
      await _repository.fail(exportId: exportId, errorCode: code);
    } catch (_) {
      // O erro original é mais relevante; a auditoria de falha é best-effort.
    }
  }

  void _checkLimit(int inputBytes) {
    if (inputBytes > maxArchiveInputBytes) {
      throw const ClubExportFailure(
        'package_too_large',
        'A exportação ultrapassa o limite de 200 MB.',
      );
    }
  }
}
