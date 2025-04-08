// lib/features/shared/widgets/full_screen_media_viewer.dart

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

// --- Visualizador de Imagem (Com correção no errorBuilder) ---
class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String title;

  const FullScreenImageViewer({
    Key? key,
    required this.imageUrl,
    this.title = 'Anexo',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          boundaryMargin: const EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  color: Colors.white,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              print("Erro ao carregar imagem no viewer: $error");
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // --- CORREÇÃO APLICADA AQUI: Removido o 'const' ---
                  Icon(
                    Icons.broken_image,
                    color: Colors.white.withOpacity(
                        0.8), // <- Linha causadora do erro original
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Text(
                      'Erro ao carregar imagem',
                      style: TextStyle(color: Colors.white.withOpacity(0.7)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// --- Visualizador de Vídeo (Sem alterações nesta correção) ---
class FullScreenVideoViewer extends StatefulWidget {
  final String videoUrl;
  final String title;

  const FullScreenVideoViewer({
    Key? key,
    required this.videoUrl,
    this.title = 'Vídeo',
  }) : super(key: key);

  @override
  _FullScreenVideoViewerState createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<FullScreenVideoViewer> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null || !uri.hasAbsolutePath || !uri.isAbsolute) {
      print("URL do vídeo inválida: ${widget.videoUrl}");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "URL do vídeo inválida.";
        });
      }
      return;
    }

    _videoPlayerController = VideoPlayerController.networkUrl(uri);

    try {
      await _videoPlayerController.initialize();
      _createChewieController();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      print("Erro ao inicializar o player de vídeo: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Erro ao carregar vídeo: ${e.toString()}";
        });
      }
    }
  }

  void _createChewieController() {
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      aspectRatio: _videoPlayerController.value.aspectRatio,
      autoPlay: true,
      looping: false,
      allowFullScreen: false,
      materialProgressColors: ChewieProgressColors(
        playedColor: Theme.of(context).primaryColor,
        handleColor: Theme.of(context).primaryColor,
        bufferedColor: Colors.grey.shade600,
        backgroundColor: Colors.grey.shade800,
      ),
      placeholder: Container(
        color: Colors.black,
        child:
            const Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      errorBuilder: (context, errorMessage) {
        return Center(
            child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Erro ao reproduzir vídeo:\n$errorMessage',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ));
      },
    );
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: _buildPlayerWidget(),
      ),
    );
  }

  Widget _buildPlayerWidget() {
    if (_isLoading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 20),
          Text('Carregando Vídeo...', style: TextStyle(color: Colors.white)),
        ],
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.error_outline, color: Colors.red, size: 48),
          SizedBox(height: 16),
          Text(_errorMessage!,
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center),
        ]),
      );
    }

    if (_chewieController != null &&
        _chewieController!.videoPlayerController.value.isInitialized) {
      return Chewie(controller: _chewieController!);
    } else {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 20),
          Text('Preparando vídeo...', style: TextStyle(color: Colors.white)),
        ],
      );
    }
  }
}

// --- Função auxiliar para abrir o visualizador (Sem alterações) ---
void openFullScreenMedia(
    BuildContext context, String url, String type, String name) {
  if (url.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('URL do anexo inválida ou vazia.'),
          backgroundColor: Colors.orange),
    );
    return;
  }

  final isVideo = type.toLowerCase() == 'video';

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => isVideo
          ? FullScreenVideoViewer(
              videoUrl: url,
              title: name,
            )
          : FullScreenImageViewer(
              imageUrl: url,
              title: name,
            ),
    ),
  );
}
