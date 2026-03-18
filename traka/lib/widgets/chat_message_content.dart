import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/chat_message_model.dart';
import '../services/chat_service.dart';

/// Konten pesan chat (teks, audio, gambar, video, barcode).
/// Dipakai di chat_room_penumpang_screen dan chat_driver_screen.
class ChatMessageContent extends StatelessWidget {
  const ChatMessageContent({
    super.key,
    required this.msg,
    required this.isMe,
    required this.barcodeSnippet,
    required this.isAudioPlaying,
    required this.onToggleAudioPlayback,
    required this.onOpenFullScreenImage,
  });

  final ChatMessageModel msg;
  final bool isMe;
  /// Snippet untuk barcode: penumpang "Scan di Data Order", driver "Tampilkan di Data Order untuk di-scan penumpang"
  final String barcodeSnippet;
  final bool isAudioPlaying;
  final Future<void> Function(ChatMessageModel msg) onToggleAudioPlayback;
  final void Function(String url) onOpenFullScreenImage;

  @override
  Widget build(BuildContext context) {
    if (msg.isText) {
      return _buildTextRow(context);
    }
    if (msg.isAudio) {
      return _buildAudioMessage(context);
    }
    if (msg.isImage) {
      return _buildImageMessage(context);
    }
    if (msg.isVideo) {
      return _buildVideoMessage(context);
    }
    if (msg.isBarcode) {
      return _buildBarcodeMessage(context);
    }
    if (msg.isVoiceCallStatus) {
      return _buildVoiceCallStatusMessage(context);
    }
    return const SizedBox.shrink();
  }

  Widget _buildTextRow(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: _buildTextContent(context, msg.text),
        ),
        if (isMe) ...[
          const SizedBox(width: 6),
          _buildStatusIcon(context, msg.status),
        ],
      ],
    );
  }

  Widget _buildVoiceCallStatusMessage(BuildContext context) {
    final status = msg.voiceCallStatus ?? 'ended';
    IconData icon;
    if (status == 'rejected') {
      icon = Icons.call_missed;
    } else if (status == 'ended' && (msg.voiceCallDurationSeconds ?? 0) > 0) {
      icon = Icons.call;
    } else {
      icon = Icons.call_missed_outgoing;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (isMe
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest)
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            msg.text,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeMessage(BuildContext context) {
    final title = msg.isBarcodePassenger ? 'Barcode penjemputan' : 'Barcode selesai';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (isMe
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest)
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.qr_code_2,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '$title — $barcodeSnippet',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Teks pesan: "Tujuan" / "Tujuan: " biru tebal; baris tarif/biaya & "Ongkosnya Rp ..." hijau tebal.
  Widget _buildTextContent(BuildContext context, String text) {
    final baseColor =
        isMe ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final blueBold = TextStyle(
      fontSize: 15,
      color: isMe
          ? const Color(0xFFBBDEFB)
          : Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.bold,
    );
    final greenBold = TextStyle(
      fontSize: 15,
      color: isMe
          ? const Color(0xFFA5D6A7)
          : (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFA5D6A7)
              : const Color(0xFF2E7D32)),
      fontWeight: FontWeight.bold,
    );
    final baseStyle = TextStyle(fontSize: 15, color: baseColor);
    final lines = text.split('\n');
    final widgets = <Widget>[];
    final isTarifLine = (String t) =>
        t == 'Mohon informasi tarif untuk rute ini.' ||
        t == 'Mohon informasi biaya pengiriman untuk rute ini.';
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (line.isNotEmpty) widgets.add(Text(line, style: baseStyle));
        continue;
      }
      if (isTarifLine(trimmed) || trimmed.startsWith('Ongkosnya Rp ')) {
        widgets.add(Text(trimmed, style: greenBold));
        continue;
      }
      if (trimmed.startsWith('Tujuan: ') || trimmed.startsWith('Tujuan ')) {
        final prefix =
            trimmed.startsWith('Tujuan: ') ? 'Tujuan: ' : 'Tujuan ';
        final rest = trimmed.substring(prefix.length);
        widgets.add(
          RichText(
            text: TextSpan(
              style: baseStyle,
              children: [
                TextSpan(text: prefix, style: blueBold),
                if (rest.isNotEmpty) TextSpan(text: rest, style: baseStyle),
              ],
            ),
          ),
        );
        continue;
      }
      widgets.add(Text(line, style: baseStyle));
    }
    if (widgets.length == 1) return widgets.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _buildStatusIcon(BuildContext context, String status) {
    final isRead = status == ChatService.statusRead;
    final isDelivered = status == ChatService.statusDelivered;
    final color = isRead
        ? const Color(0xFFBBDEFB)
        : Theme.of(context).colorScheme.surface;
    final icon = (isDelivered || isRead) ? Icons.done_all : Icons.done;
    return Icon(icon, size: 16, color: color);
  }

  Widget _buildAudioMessage(BuildContext context) {
    final duration = msg.audioDuration ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            isAudioPlaying ? Icons.pause : Icons.play_arrow,
            color: isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => onToggleAudioPlayback(msg),
        ),
        const SizedBox(width: 4),
        Text(
          _formatDuration(duration),
          style: TextStyle(
            fontSize: 13,
            color: isMe
                ? Colors.white70
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 6),
          _buildStatusIcon(context, msg.status),
        ],
      ],
    );
  }

  Widget _buildImageMessage(BuildContext context) {
    final imageUrl = msg.mediaUrl ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => onOpenFullScreenImage(imageUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 200,
                height: 200,
                color: Theme.of(context).colorScheme.outline,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                width: 200,
                height: 200,
                color: Theme.of(context).colorScheme.outline,
                child: const Icon(Icons.error),
              ),
            ),
          ),
        ),
        if (isMe) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [_buildStatusIcon(context, msg.status)],
          ),
        ],
      ],
    );
  }

  Widget _buildVideoMessage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Container(
                width: 200,
                height: 200,
                color: Theme.of(context).colorScheme.onSurface,
                child: msg.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: msg.thumbnailUrl!,
                        fit: BoxFit.cover,
                      )
                    : const Center(
                        child: Icon(
                          Icons.videocam,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
              ),
              const Center(
                child: Icon(
                  Icons.play_circle_filled,
                  color: Colors.white70,
                  size: 48,
                ),
              ),
            ],
          ),
        ),
        if (isMe) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [_buildStatusIcon(context, msg.status)],
          ),
        ],
      ],
    );
  }

  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
