import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_view/photo_view.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/document.dart';
import 'package:dio/dio.dart';

class SharedDocumentViewerPage extends StatefulWidget {
  final Document document;

  const SharedDocumentViewerPage({super.key, required this.document});

  @override
  State<SharedDocumentViewerPage> createState() =>
      _SharedDocumentViewerPageState();
}

class _SharedDocumentViewerPageState extends State<SharedDocumentViewerPage> {
  @override
  void initState() {
    super.initState();
    // Disable screenshots if not allowed
    if (!widget.document.isScreenshotAllowed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    // Re-enable screenshots when leaving the page
    if (!widget.document.isScreenshotAllowed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _downloadDocument() async {
    if (!widget.document.isDownloadable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download is not allowed for this document'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final dir = await getExternalStorageDirectory();
      final downloadsDir = dir ?? await getApplicationDocumentsDirectory();
      final filePath = '${downloadsDir.path}/${widget.document.fileName}';

      final dio = Dio();
      await dio.download(
        widget.document.downloadUrl,
        filePath,
        options: Options(responseType: ResponseType.bytes),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded to $filePath'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading document: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _isImageFile(String fileName) {
    final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
    final extension = fileName.toLowerCase().split('.').last;
    return imageExtensions.contains(extension);
  }

  Widget _buildDocumentViewer() {
    if (_isImageFile(widget.document.fileName)) {
      // Render image directly in the app with zoom functionality
      return Container(
        width: double.infinity,
        height: 400,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: PhotoView(
                imageProvider: NetworkImage(widget.document.downloadUrl),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3.0,
                initialScale: PhotoViewComputedScale.contained,
                backgroundDecoration: BoxDecoration(
                  color: Colors.grey.shade100,
                ),
                loadingBuilder: (context, event) {
                  return SizedBox(
                    height: 400,
                    child: Center(
                      child: CircularProgressIndicator(
                        value:
                            event == null
                                ? 0
                                : event.cumulativeBytesLoaded /
                                    (event.expectedTotalBytes ?? 1),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return SizedBox(
                    height: 400,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error,
                            size: 64,
                            color: Colors.red.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load image',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.red.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final scaffoldMessenger = ScaffoldMessenger.of(
                                context,
                              );
                              try {
                                final Uri url = Uri.parse(
                                  widget.document.downloadUrl,
                                );
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(
                                    url,
                                    mode: LaunchMode.inAppBrowserView,
                                  );
                                } else {
                                  throw 'Could not launch $url';
                                }
                              } catch (e) {
                                if (mounted) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error opening document: $e',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('Open in Browser'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(
                  onPressed: () => _openFullscreenImage(),
                  icon: const Icon(Icons.fullscreen, color: Colors.white),
                  tooltip: 'View Fullscreen',
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Pinch to zoom • Tap fullscreen for better view',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      );
    } else if (widget.document.fileName.toLowerCase().endsWith('.pdf')) {
      // PDF preview using flutter_pdfview
      return FutureBuilder<File>(
        future: _downloadPdfToFile(widget.document.downloadUrl),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Failed to load PDF'));
          } else if (!snapshot.hasData) {
            return Center(child: Text('PDF not available'));
          }
          return Container(
            width: double.infinity,
            height: 400,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: PDFView(
              filePath: snapshot.data!.path,
              enableSwipe: true,
              swipeHorizontal: false,
              autoSpacing: true,
              pageFling: true,
            ),
          );
        },
      );
    } else {
      // For non-image, non-pdf files, show a placeholder
      return Container(
        width: double.infinity,
        height: 400,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insert_drive_file, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                widget.document.fileName,
                style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Preview not available',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<File> _downloadPdfToFile(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download PDF');
    }
    final bytes = response.bodyBytes;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${widget.document.fileName}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  void _openFullscreenImage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => FullscreenImageViewer(
              imageUrl: widget.document.downloadUrl,
              title:
                  widget.document.name.isNotEmpty
                      ? widget.document.name
                      : 'Image',
            ),
      ),
    );
  }

  Future<void> _shareDocument() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.document.downloadUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document link copied to clipboard'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing document: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.document.name.isNotEmpty
              ? widget.document.name
              : 'Shared Document',
        ),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          if (widget.document.isDownloadable)
            IconButton(
              onPressed: _downloadDocument,
              icon: const Icon(Icons.download),
              tooltip: 'Download',
            ),
          IconButton(
            onPressed: _shareDocument,
            icon: const Icon(Icons.share),
            tooltip: 'Share Link',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Document Info Card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Document Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      'Name',
                      widget.document.name.isNotEmpty
                          ? widget.document.name
                          : 'Untitled',
                    ),
                    _buildInfoRow(
                      'Type',
                      widget.document.type.isNotEmpty
                          ? widget.document.type
                          : 'N/A',
                    ),
                    _buildInfoRow(
                      'File Name',
                      widget.document.fileName.isNotEmpty
                          ? widget.document.fileName
                          : 'N/A',
                    ),
                    _buildInfoRow(
                      'Expires',
                      '${widget.document.expiryDate.day.toString().padLeft(2, '0')}/${widget.document.expiryDate.month.toString().padLeft(2, '0')}/${widget.document.expiryDate.year}',
                    ),
                    if (widget.document.tags.isNotEmpty)
                      _buildInfoRow('Tags', widget.document.tags.join(', ')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sharing Restrictions Card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.security,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Sharing Restrictions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildRestrictionRow(
                      'Download',
                      widget.document.isDownloadable,
                      widget.document.isDownloadable
                          ? 'Allowed'
                          : 'Not Allowed',
                    ),
                    _buildRestrictionRow(
                      'Screenshots',
                      widget.document.isScreenshotAllowed,
                      widget.document.isScreenshotAllowed
                          ? 'Allowed'
                          : 'Not Allowed',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Document Viewer Card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.visibility,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Document Viewer',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDocumentViewer(),
                  ],
                ),
              ),
            ),

            if (!widget.document.isScreenshotAllowed)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Screenshots are disabled for this document',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }

  Widget _buildRestrictionRow(String label, bool isAllowed, String status) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Icon(
            isAllowed ? Icons.check_circle : Icons.cancel,
            color: isAllowed ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
              color: isAllowed ? Colors.green.shade700 : Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class FullscreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String title;

  const FullscreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
        elevation: 0,
      ),
      body: PhotoView(
        imageProvider: NetworkImage(imageUrl),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 5.0,
        initialScale: PhotoViewComputedScale.contained,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (context, event) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.white),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load image',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}