import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/api/study_controller.dart';
import '../../shared/components.dart';

class PdfScreen extends StatefulWidget {
  final StudyController controller;
  final Map<String, dynamic> document;
  const PdfScreen({
    super.key,
    required this.controller,
    required this.document,
  });
  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  late Future<Uint8List> bytes = widget.controller.documentBytes(
    widget.document['id'],
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          widget.document['filename'],
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      Expanded(
        child: FutureBuilder<Uint8List>(
          future: bytes,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ErrorState(message: '${snapshot.error}'),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => setState(
                        () => bytes = widget.controller.documentBytes(
                          widget.document['id'],
                        ),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            if (!snapshot.hasData)
              return const LoadingState(label: 'Opening your private PDF…');
            return PdfViewer.data(
              snapshot.data!,
              sourceName:
                  '${widget.controller.account}/${widget.document['id']}',
            );
          },
        ),
      ),
    ],
  );
}
