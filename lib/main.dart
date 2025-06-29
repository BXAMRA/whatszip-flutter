import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'dart:convert'; // For utf8 decoding and base64
import 'dart:io'; // Required for File class
import 'package:flutter/services.dart'; // For Clipboard
import 'dart:typed_data'; // For Uint8List
import 'package:url_launcher/url_launcher.dart'; // Import for opening URLs/files across platforms
import 'package:flutter/foundation.dart' show kIsWeb; // For platform detection
import 'package:path_provider/path_provider.dart'; // For temporary directory
import 'package:audioplayers/audioplayers.dart'; // Import for audio playback
import 'package:video_player/video_player.dart'; // Import for video playback
import 'package:chewie/chewie.dart'; // Import for Chewie video controls
import 'package:flutter/gestures.dart'; // Import for TapGestureRecognizer


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhatsZip Viewer',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Inter', // Applying Inter font
      ),
      home: const WhatsZipViewerScreen(),
    );
  }
}

// Helper class to represent a part of the message (either text or a clickable link)
class TextPart {
  final String text;
  final String? url; // If this part is a URL, store the URL string

  TextPart({required this.text, this.url});

  bool get isLink => url != null;
}

// Class to represent a single chat message
class ChatMessage {
  final String sender;
  final String message; // Keep original message for full copy to clipboard
  final DateTime timestamp;
  final Uint8List? imageData; // For displaying images directly
  final String? mediaFileName; // For general media files (documents, videos etc.)
  final String? mediaType; // e.g., 'image', 'document', 'video', 'audio'
  final List<TextPart> parsedMessageParts; // New field for structured text/links
  final bool isSystemMessage; // New field to identify system messages

  ChatMessage({
    required this.sender,
    required this.message,
    required this.timestamp,
    this.imageData,
    this.mediaFileName,
    this.mediaType,
    required this.parsedMessageParts, // This will be generated during parsing
    this.isSystemMessage = false, // Default to false
  });
}

// New screen for viewing images
class ImageViewerScreen extends StatelessWidget {
  final Uint8List imageData;
  final String fileName;

  const ImageViewerScreen({
    Key? key,
    required this.imageData,
    required this.fileName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal,
        iconTheme: const IconThemeData(color: Colors.white), // Set back button color to white
      ),
      body: Center(
        // InteractiveViewer allows zooming and panning of the image
        child: InteractiveViewer(
          boundaryMargin: const EdgeInsets.all(20.0),
          minScale: 0.1,
          maxScale: 4.0,
          child: Image.memory(
            imageData,
            fit: BoxFit.contain, // Ensure the image fits within the view initially
          ),
        ),
      ),
    );
  }
}

// New screen for playing video files
class VideoPlayerScreen extends StatefulWidget {
  final Uint8List videoData;
  final String fileName;

  const VideoPlayerScreen({
    Key? key,
    required this.videoData,
    required this.fileName,
  }) : super(key: key);

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  String? _tempFilePath;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      // Write video bytes to a temporary file
      final Directory tempDir = await getTemporaryDirectory();
      _tempFilePath = '${tempDir.path}/${widget.fileName}';
      final File tempFile = File(_tempFilePath!);
      await tempFile.writeAsBytes(widget.videoData);

      _videoPlayerController = VideoPlayerController.file(tempFile);
      await _videoPlayerController.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );
      setState(() {});
    } catch (e) {
      print('Error initializing video player: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing video: $e')),
      );
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    // Optionally delete the temporary file after disposal
    if (_tempFilePath != null && File(_tempFilePath!).existsSync()) {
      File(_tempFilePath!).delete().catchError((e) => print('Error deleting temp video file: $e'));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
          ? Center(
              child: AspectRatio(
                aspectRatio: _videoPlayerController.value.aspectRatio,
                child: Chewie(
                  controller: _chewieController!,
                ),
              ),
            )
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)),
                  SizedBox(height: 20),
                  Text('Loading video...', style: TextStyle(color: Colors.black54)),
                ],
              ),
            ),
    );
  }
}


// New widget for playing audio files directly in the message bubble
class AudioPlayerWidget extends StatefulWidget {
  final Uint8List audioData;
  final String fileName;
  final Color textColor;
  final Color primaryColor;

  const AudioPlayerWidget({
    Key? key,
    required this.audioData,
    required this.fileName,
    required this.textColor,
    required this.primaryColor,
  }) : super(key: key);

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _audioPlayer;
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    // Set audio source from bytes
    _setAudioSource();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _playerState = state;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) {
        setState(() {
          _duration = newDuration;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) {
        setState(() {
          _position = newPosition;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _playerState = PlayerState.stopped;
          _position = Duration.zero; // Reset position
        });
        _audioPlayer.stop(); // Ensure stop is called
        _audioPlayer.seek(Duration.zero); // Reset to beginning
      }
    });
  }

  Future<void> _setAudioSource() async {
    try {
      // Save bytes to a temporary file and play from its path
      final Directory tempDir = await getTemporaryDirectory();
      final File tempFile = File('${tempDir.path}/${widget.fileName}');
      await tempFile.writeAsBytes(widget.audioData);

      // Use setSource with DeviceFileSource for local file paths
      await _audioPlayer.setSource(DeviceFileSource(tempFile.path));
    } catch (e) {
      print('Error setting audio source: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing audio: $e')),
      );
    }
  }


  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    final hours = twoDigits(d.inHours);
    if (d.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                _playerState == PlayerState.playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: widget.primaryColor,
                size: 30,
              ),
              onPressed: () async {
                if (_playerState == PlayerState.playing) {
                  await _audioPlayer.pause();
                } else {
                  await _audioPlayer.resume();
                }
              },
            ),
            Expanded(
              child: Slider(
                min: 0.0,
                max: _duration.inMilliseconds.toDouble(),
                value: _position.inMilliseconds.toDouble(),
                onChanged: (value) async {
                  final position = Duration(milliseconds: value.toInt());
                  await _audioPlayer.seek(position);
                  // No need to play immediately after seeking, let the user manually play if paused
                },
                activeColor: widget.primaryColor,
                inactiveColor: widget.primaryColor.withOpacity(0.3),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: TextStyle(fontSize: 12, color: widget.textColor),
              ),
              Text(
                _formatDuration(_duration),
                style: TextStyle(fontSize: 12, color: widget.textColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4.0),
        Text(
          widget.fileName,
          style: TextStyle(
            fontSize: 14,
            color: widget.textColor.withOpacity(0.8),
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class WhatsZipViewerScreen extends StatefulWidget {
  const WhatsZipViewerScreen({super.key});

  @override
  State<WhatsZipViewerScreen> createState() => _WhatsZipViewerScreenState();
}

class _WhatsZipViewerScreenState extends State<WhatsZipViewerScreen> {
  List<ChatMessage> _chatMessages = [];
  String? _userName;
  bool _isLoading = false;
  String _statusMessage = 'Select a zip file to view chat.';
  Map<String, Uint8List> _mediaFiles = {}; // Stores media data keyed by filename

  // Function to pick a zip file
  Future<void> _pickZipFile() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Picking file...';
      _chatMessages = []; // Clear previous chat
      _mediaFiles = {}; // Clear previous media files
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null && result.files.single.path != null) {
        String? filePath = result.files.single.path;
        if (filePath != null) {
          await _processZipFile(filePath);
        } else {
          _showErrorDialog('File path is null. Please try again.');
        }
      } else {
        setState(() {
          _isLoading = false;
          _statusMessage = 'File selection cancelled.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error picking file: $e';
      });
      _showErrorDialog('Error picking file: $e');
    }
  }

  // Function to process the selected zip file
  Future<void> _processZipFile(String filePath) async {
    setState(() {
      _statusMessage = 'Reading zip file and extracting media...';
    });
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? chatFile;
      Map<String, Uint8List> extractedMedia = {};

      for (final file in archive) {
        if (file.isFile) {
          // Identify the chat file
          if (file.name.toLowerCase().contains('chat') && file.name.endsWith('.txt')) {
            chatFile = file;
          } else {
            // Store other files as media
            extractedMedia[file.name] = file.content as Uint8List;
          }
        }
      }
      _mediaFiles = extractedMedia; // Store extracted media

      if (chatFile != null) {
        setState(() {
          _statusMessage = 'Extracting chat content...';
        });
        if (chatFile.content != null) {
          final chatContentRaw = utf8.decode(chatFile.content as List<int>);

          // --- START: Clean non-displayable characters ---
          // Remove carriage returns to normalize newlines to '\n'
          String chatContentCleaned = chatContentRaw.replaceAll('\r', '');
          // Remove specific known problematic invisible Unicode characters
          chatContentCleaned = chatContentCleaned.replaceAll('‎', ''); // U+200E (Left-to-Right Mark)
          chatContentCleaned = chatContentCleaned.replaceAll(' ', ''); // U+202F (Narrow No-Break Space)
          chatContentCleaned = chatContentCleaned.replaceAll('﻿', ''); // U+FEFF (Byte Order Mark)

          // Remove all other ASCII control characters except newline (\n) and tab (\t)
          // Matches characters from U+0000-U+0008, U+000B-U+000C, U+000E-U+001F, and U+007F
          chatContentCleaned = chatContentCleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
          // --- END: Clean non-displayable characters ---

          _parseChatContent(chatContentCleaned);
        } else {
          setState(() {
            _isLoading = false;
            _statusMessage = 'Chat file content is empty.';
          });
          _showErrorDialog('Error: Chat file content is empty.');
        }
      } else {
        setState(() {
          _isLoading = false;
          _statusMessage = 'No chat .txt file found in the zip.';
        });
        _showErrorDialog('Error: No chat .txt file found in the zip. '
            'Please ensure the zip contains a .txt file with "chat" in its name.');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error processing zip file: $e';
      });
      _showErrorDialog('Error processing zip file: $e');
    }
  }

  // Function to determine if a message should be discarded
  bool _shouldDiscardMessage(String messageContent) {
    // Remove hidden chars (U+200E, U+202F) for comparison
    final cleanedMessage = messageContent.toLowerCase().trim().replaceAll('‎', '').replaceAll(' ', '');
    return cleanedMessage == 'null' ||
           cleanedMessage.contains('messages and calls are end-to-end');
  }

  // Function to parse chat content and extract messages and participants
  void _parseChatContent(String content) {
    List<ChatMessage> parsedMessages = [];
    Set<String> uniqueParticipants = {};

    // Regex for format 1: [DD.MM.YYYY, HH:MM:SS AM/PM] Sender: Message
    // Using ([\s\S]*) for message content to capture everything including newlines.
    final RegExp regexFormat1 = RegExp(
      r'^[\s\u200E\u202F]?\[(\d{1,2}[./]\d{1,2}[./]\d{2,4}),\s*(\d{1,2}:\d{2}:\d{2})\s*(AM|PM)?\]\s*([^:]+):\s*([\s\S]*)',
      multiLine: true,
    );

    // Regex for format 2: MM/DD/YY, HH:MM AM/PM - Sender: Message
    // Using ([\s\S]*) for message content to capture everything including newlines.
    final RegExp regexFormat2 = RegExp(
      r'^[\s\u200E\u202F]?(\d{1,2}/\d{1,2}/\d{2,4}),\s*(\d{1,2}:\d{2}\s*(?:AM|PM)?)\s*-\s*([^:]+):\s*([\s\S]*)',
      multiLine: true,
    );

    // NEW COMBINED Regex to find attachments for both formats:
    // 1. "filename.ext (file attached)" - filename is group 1
    // 2. "<attached: filename.ext>" - filename is group 3
    final RegExp attachmentTagRegex = RegExp(
      r'(?:([\w\-.%]+\.(jpg|jpeg|png|gif|mp4|3gp|pdf|doc|docx|xls|xlsx|ppt|pptx|opus|webp))\s+\(file attached\))|' + // Added webp
      r'(?:<attached:\s*([\w\-.%]+\.(jpg|jpeg|png|gif|mp4|3gp|pdf|doc|docx|xls|xlsx|ppt|pptx|opus|webp)))', // Added webp
      caseSensitive: false,
    );

    // Revised Regex to detect URLs: requires http(s):// or www. prefix, or a more specific domain pattern
    final RegExp urlRegex = RegExp(
      r'(https?:\/\/[^\s]+)|(www\.[^\s]+)|([a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:\.[a-zA-Z]{2,})?(?:\/[^\s]*)?)', // Improved regex for domains and TLDs
      caseSensitive: false,
    );

    // Regex to detect system messages like "created this group", "added you", "removed", "You left" etc.
    // Using triple quotes (r'''...''') for the raw string to handle inner single and double quotes literally.
    final RegExp _systemMessageRegex = RegExp(
      r'''^(?:You|.+?)(?: created this group| added you| removed .+?| left| changed the group icon| changed the group's subject to ".+?"| changed the group's settings to allow only admins to edit this group's settings| changed the group's settings to allow only admins to send messages to this group| joined using this group's invite link| changed their phone number to a new number\. Tap to message or add the new number\.| changed their phone number| was added| were added| restored this group| joined the group| left the group| ended the call\.| deleted this group| missed video call| missed voice call)''',
      caseSensitive: false,
    );


    List<String> lines = content.split('\n');
    String? currentSender;
    String currentMessageContent = ''; // Initialize as empty string, not null
    DateTime? currentTimestamp;

    // Helper function to process and add messages
    void _addCurrentMessage() {
      // Only add if there's a sender, timestamp, and non-empty message content (after cleaning)
      if (currentSender != null && currentTimestamp != null && currentMessageContent.isNotEmpty) {
        final cleanedMessageContent = currentMessageContent.replaceAll('‎', '').replaceAll(' ', '');

        if (!_shouldDiscardMessage(cleanedMessageContent)) {
          // Check if it's a system message before processing attachments or links
          if (_systemMessageRegex.hasMatch(cleanedMessageContent)) {
            parsedMessages.add(ChatMessage(
              sender: currentSender!,
              message: cleanedMessageContent.trim(),
              timestamp: currentTimestamp!,
              parsedMessageParts: [TextPart(text: cleanedMessageContent.trim())], // System messages are plain text
              isSystemMessage: true,
            ));
            currentSender = null;
            currentMessageContent = '';
            currentTimestamp = null;
            return; // Skip further processing for system messages
          }


          final List<RegExpMatch> attachmentMatches = attachmentTagRegex.allMatches(cleanedMessageContent).toList();

          String messageTextWithoutAttachments = cleanedMessageContent;
          List<String> extractedFileNames = [];

          for (var match in attachmentMatches) {
            String fileName;
            // Determine which group contains the filename based on which format matched
            if (match.group(1) != null) { // If Format 1 matched (e.g., "file.jpg (file attached)")
              fileName = match.group(1)!;
            } else if (match.group(3) != null) { // If Format 2 matched (e.g., "<attached: file.jpg>")
              fileName = match.group(3)!;
            } else {
              continue; // Should not happen if regex is correct, but good for safety
            }

            extractedFileNames.add(fileName);
            // Remove the attachment tag from the message content
            messageTextWithoutAttachments = messageTextWithoutAttachments.replaceAll(match.group(0)!, '');
            // After removing the attachment tag, also remove any remaining leading/trailing '>' or '<'
            messageTextWithoutAttachments = messageTextWithoutAttachments.trim().replaceAll(RegExp(r'^[<>]+|[<>]+$'), '');
          }

          // --- Process messageTextWithoutAttachments for URLs ---
          List<TextPart> messageParts = [];
          String remainingText = messageTextWithoutAttachments.trim();

          while (true) {
            Match? urlMatch = urlRegex.firstMatch(remainingText);
            if (urlMatch == null) {
              if (remainingText.isNotEmpty) {
                messageParts.add(TextPart(text: remainingText));
              }
              break;
            }

            // Add text before the URL
            if (urlMatch.start > 0) {
              messageParts.add(TextPart(text: remainingText.substring(0, urlMatch.start)));
            }

            // Add the URL part
            String detectedUrl = urlMatch.group(0)!;
            // Prepend http if not present and if it looks like a bare domain (e.g., example.com)
            if (!detectedUrl.startsWith('http://') && !detectedUrl.startsWith('https://') && !detectedUrl.startsWith('www.')) {
              detectedUrl = 'http://$detectedUrl';
            }
            messageParts.add(TextPart(text: urlMatch.group(0)!, url: detectedUrl));

            // Update remaining text
            remainingText = remainingText.substring(urlMatch.end);
          }
          // --- End URL processing ---


          // Add a message for the remaining text content if it's not empty,
          // or if there were no attachments and some non-discarded content.
          if (messageTextWithoutAttachments.isNotEmpty || (extractedFileNames.isEmpty && cleanedMessageContent.isNotEmpty)) {
            parsedMessages.add(ChatMessage(
              sender: currentSender!,
              message: messageTextWithoutAttachments.trim(), // Keep original clean message here
              timestamp: currentTimestamp!,
              parsedMessageParts: messageParts, // Pass the new list of parts
              isSystemMessage: false, // Not a system message
            ));
          }

          for (String fileName in extractedFileNames) {
            String fileExtension = fileName.split('.').last.toLowerCase();
            Uint8List? imageData;
            String? mediaType;

            if (_mediaFiles.containsKey(fileName)) {
              final mediaBytes = _mediaFiles[fileName]!;
              if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(fileExtension)) { // Added webp
                imageData = mediaBytes;
                mediaType = 'image';
              } else if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'].contains(fileExtension)) {
                mediaType = 'document';
              } else if (['mp4', '3gp'].contains(fileExtension)) {
                mediaType = 'video';
              } else if (fileExtension == 'opus') { // Handle opus files
                mediaType = 'audio';
              } else {
                mediaType = 'other';
              }
            } else {
              mediaType = 'missing';
            }

            // For attachment messages, the message text itself is empty, but we still need parsedMessageParts
            // It will be an empty list for pure attachments, or contain text if there's text along with the attachment
            parsedMessages.add(ChatMessage(
              sender: currentSender!,
              message: '', // Attachment messages have empty text content themselves
              timestamp: currentTimestamp!,
              imageData: imageData,
              mediaFileName: fileName,
              mediaType: mediaType,
              parsedMessageParts: messageParts.isEmpty && messageTextWithoutAttachments.isEmpty
                  ? [] // Empty for pure attachments
                  : [TextPart(text: messageTextWithoutAttachments.trim())], // Or if there was text combined
              isSystemMessage: false, // Not a system message
            ));
          }
        }
      }
      currentSender = null;
      currentMessageContent = ''; // Reset to empty string
      currentTimestamp = null;
    }


    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      Match? format1Match = regexFormat1.firstMatch(line);
      Match? format2Match = regexFormat2.firstMatch(line);

      String? datePart, timePart, senderName;
      bool isNewMessageLine = false;
      String newMessageText = ''; // Temporarily hold the message text for the new line

      if (format1Match != null) {
        datePart = format1Match.group(1)!;
        timePart = '${format1Match.group(2)!}${format1Match.group(3) != null ? ' ${format1Match.group(3)}' : ''}';
        senderName = format1Match.group(4)!;
        newMessageText = format1Match.group(5) ?? ''; // Group 5 for message text in regexFormat1. Use ?? '' for safety.
        isNewMessageLine = true;
      } else if (format2Match != null) {
        datePart = format2Match.group(1)!;
        timePart = format2Match.group(2)!;
        senderName = format2Match.group(3)!;
        newMessageText = format2Match.group(4) ?? ''; // Group 4 for message text in regexFormat2. Use ?? '' for safety.
        isNewMessageLine = true;
      }

      if (isNewMessageLine) {
        _addCurrentMessage(); // Process the accumulated message

        currentSender = senderName;
        currentMessageContent = newMessageText; // Assign the non-null new message text
        // Timestamp parsing for the new message line
        try {
          List<String> dateTimeFormats = [
            'dd.MM.yyyy hh:mm:ss a', // For [DD.MM.YYYY, HH:MM:SS PM] with optional AM/PM
            'dd/MM/yyyy hh:mm:ss a', // Variation with slash
            'dd/MM/yy hh:mm:ss', // Older standard without AM/PM
            'MM/dd/yy hh:mm a',   // For "M/D/YY, H:MM AM/PM"
            'MM/dd/yyyy hh:mm a', // For "MM/DD/YYYY, H:MM AM/PM"
            'dd/MM/yyyy HH:mm',
            'MM/dd/yyyy hh:mm',
            'dd/MM/yy hh:mm a',
            'dd.MM.yyyy HH:mm:ss', // For [DD.MM.YYYY, HH:MM:SS] without AM/PM
          ];

          String rawDateTime = '$datePart $timePart'.trim();
          // Clean rawDateTime: replace narrow no-break space (U+202F) and Left-to-Right Mark (U+200E) with regular space
          rawDateTime = rawDateTime.replaceAll(' ', ' ').replaceAll('\u200E', '');


          bool parsedSuccessfully = false;

          // Handle 2-digit years by prepending '20' if necessary
          if (datePart != null) {
            // Simplified heuristic for 2-digit year (e.g., 22/03/22)
            final parts = datePart.split(RegExp(r'[./]'));
            if (parts.length == 3 && parts[2].length == 2) {
              rawDateTime = '${parts[0]}${datePart.contains('.') ? '.' : '/'}${parts[1]}${datePart.contains('.') ? '.' : '/'}20${parts[2]} $timePart'.trim();
              // Add specific formats that might now match with 4-digit year if 2-digit year was updated
              dateTimeFormats.insert(0, 'MM/dd/yyyy hh:mm a');
              dateTimeFormats.insert(1, 'dd.MM.yyyy HH:mm:ss');
              dateTimeFormats.insert(2, 'dd/MM/yyyy HH:mm:ss');
            }
          }


          for (String format in dateTimeFormats) {
            try {
              currentTimestamp = DateFormat(format).parse(rawDateTime);
              parsedSuccessfully = true;
              break;
            } catch (_) {
              // Keep trying other formats
            }
          }

          if (!parsedSuccessfully) {
            print('Warning: Could not parse timestamp for line: "$line" using extracted datetime "$rawDateTime". Falling back to current time.');
            currentTimestamp = DateTime.now(); // Fallback
          }

        } catch (e) {
          print('Error during timestamp parsing for line: "$line" - $e');
          currentTimestamp = DateTime.now(); // Fallback
        }

        if (currentSender != null) {
          uniqueParticipants.add(currentSender!);
        }
      } else { // This line is a continuation or an unparsable line not starting with a timestamp
        // Only append if there's an active message being built (i.e., currentSender and currentTimestamp are not null)
        if (currentSender != null && currentTimestamp != null) {
          currentMessageContent += '\n$line';
        }
        // If currentSender or currentTimestamp is null here, it means we haven't started a message yet,
        // or the previous message was already finalized and this line is malformed or extraneous.
        // In such cases, we ignore the line for parsing.
      }
    }

    // Add the last message after the loop finishes
    _addCurrentMessage();

    // Sort messages by timestamp to ensure correct order (oldest first for forward display)
    parsedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    setState(() {
      _chatMessages = parsedMessages;
      _isLoading = false;
      _statusMessage = 'Chat loaded successfully.';
    });

    if (uniqueParticipants.isNotEmpty) {
      _showNameSelectionDialog(uniqueParticipants.toList());
    } else {
      if (parsedMessages.isNotEmpty) {
        _showErrorDialog('No participants found in chat messages, though some content was parsed. Unable to determine your name.');
      } else {
        _showErrorDialog('No recognizable chat messages or participants found in the file. Please check the chat file format.');
      }
    }
  }

  // Function to show a dialog for user to select their name
  void _showNameSelectionDialog(List<String> participants) {
    showDialog(
      context: context,
      barrierDismissible: false, // User must select a name
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          title: const Text('Select Your Name', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: participants.map((name) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _userName = name;
                      });
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.teal, // Button background color
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      elevation: 3,
                    ),
                    child: Text(name, style: const TextStyle(fontSize: 16)),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // Function to show a custom error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
          title: const Text('Error', style: TextStyle(color: Colors.red)),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK', style: TextStyle(color: Colors.teal)),
            ),
          ],
        );
      },
    );
  }

  // Function to copy message details to clipboard
  void _copyMessageToClipboard(ChatMessage message) {
    final String formattedTimestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(message.timestamp);
    String textToCopy = 'Sender: ${message.sender}\nMessage: ${message.message}';
    if (message.mediaFileName != null) {
      textToCopy += '\nAttachment: ${message.mediaFileName}';
    }
    textToCopy += '\nTimestamp: $formattedTimestamp';
    Clipboard.setData(ClipboardData(text: textToCopy));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Message copied to clipboard!'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.teal.shade700,
      ),
    );
  }

  // Function to open attachment (platform-agnostic using url_launcher for non-images/audio/video, native viewer for images/videos)
  void _openAttachment(ChatMessage message) async {
    if (message.mediaFileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No attachment to open for this message.')),
      );
      return;
    }

    final String fileName = message.mediaFileName!;
    final Uint8List? mediaBytes = _mediaFiles[fileName];

    if (mediaBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: Attachment "$fileName" not found in the zip file.')),
      );
      return;
    }

    // Handle image attachments with an internal viewer screen
    if (message.mediaType == 'image' && message.imageData != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageViewerScreen(
            imageData: message.imageData!,
            fileName: message.mediaFileName!,
          ),
        ),
      );
      return; // Image handled internally
    }

    // Handle video attachments with an internal player screen
    if (message.mediaType == 'video') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
            videoData: mediaBytes, // Pass the video bytes
            fileName: message.mediaFileName!,
          ),
        ),
      );
      return; // Video handled internally
    }

    // Audio files are handled by the inline player, so no external opening
    if (message.mediaType == 'audio') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio files are played inline.')),
      );
      return;
    }


    // For other media types (documents, etc.), use url_launcher
    final String fileExtension = fileName.split('.').last.toLowerCase();
    String mimeType;

    switch (fileExtension) {
      case 'pdf':
        mimeType = 'application/pdf';
        break;
      case 'doc':
      case 'docx':
        mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        break;
      case 'xls':
      case 'xlsx':
        mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        break;
      case 'ppt':
      case 'pptx':
        mimeType = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
        break;
      default:
        mimeType = 'application/octet-stream'; // Generic binary file
        break;
    }

    try {
      if (kIsWeb) {
        // Web: Use data URL
        final String base64Data = base64Encode(mediaBytes);
        final String dataUrl = 'data:$mimeType;base64,$base64Data';
        if (await canLaunchUrl(Uri.parse(dataUrl))) {
          await launchUrl(Uri.parse(dataUrl));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch $fileName on web. No app to handle this file type.')),
          );
        }
      } else {
        // Native (iOS, Android, Desktop): Save to temp file and launch file path
        final Directory tempDir = await getTemporaryDirectory();
        final String tempPath = '${tempDir.path}/$fileName';
        final File tempFile = File(tempPath);
        await tempFile.writeAsBytes(mediaBytes);

        final Uri fileUri = Uri.file(tempFile.path); // Use Uri.file for local paths

        if (await canLaunchUrl(fileUri)) {
          await launchUrl(fileUri);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch $fileName. No app to handle this file type locally.')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error launching attachment: $e')),
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening attachment: $fileName')),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal, // WhatsApp primary color
        title: const Text(
          'WhatsZip Viewer',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: false, // Align title to the left
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _isLoading ? null : _pickZipFile, // Disable button while loading
            tooltip: 'Select Zip File',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: NetworkImage('https://placehold.co/600x800/E0E0E0/555555?text=ChatBackground'), // Placeholder background
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            // Display loading status or instructions
            if (_isLoading || _chatMessages.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isLoading)
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500, // Changed to FontWeight.w500
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              // Display chat messages if loaded
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  reverse: false, // Display oldest messages at the top
                  itemCount: _chatMessages.length,
                  itemBuilder: (context, index) {
                    final message = _chatMessages[index];
                    final bool isMe = message.sender == _userName;
                    // Determine colors for the message bubble based on sender
                    final Color bubbleColor = isMe ? const Color(0xFF075E54) : const Color(0xFFDCF8C6);
                    final Color textColor = isMe ? Colors.white : Colors.black;
                    final Color secondaryTextColor = isMe ? Colors.white70 : Colors.black54;


                    List<Widget> widgets = [];

                    // Check if the date has changed from the previous message
                    if (index == 0 || // It's the very first message
                        message.timestamp.day != _chatMessages[index - 1].timestamp.day ||
                        message.timestamp.month != _chatMessages[index - 1].timestamp.month ||
                        message.timestamp.year != _chatMessages[index - 1].timestamp.year) {
                      widgets.add(
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10.0),
                          child: Center(
                            child: Chip(
                              label: Text(
                                DateFormat('MMMM dd,yyyy').format(message.timestamp),
                                style: const TextStyle(color: Colors.black, fontSize: 12), // Black text
                              ),
                              backgroundColor: const Color(0xFFECE5DD), // #ECE5DD background
                            ),
                          ),
                        ),
                      );
                    }

                    // Render system messages as a centered chip
                    if (message.isSystemMessage) {
                      widgets.add(
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Center(
                            child: Chip(
                              label: Text(
                                message.message,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54, // Darker grey for system messages
                                ),
                                textAlign: TextAlign.center,
                              ),
                              backgroundColor: Colors.grey[300], // Light grey background
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ),
                      );
                    } else {
                      String displayMessageContent = message.message;
                      IconData? callIcon;
                      bool isAttachmentMessage = message.mediaFileName != null;
                      bool isCallMessage = false; // Flag to indicate if it's a call message

                      // Regex to robustly capture call status/duration, handling hidden characters
                      final RegExp voiceCallRegex = RegExp(r'^(?:[\s\u200E\u202F])?(Voice call|Missed voice call|Silenced voice call),?\s*(.*)');
                      final Match? callMatch = voiceCallRegex.firstMatch(message.message);

                      if (callMatch != null) {
                        isCallMessage = true; // Set flag
                        String callType = callMatch.group(1)!; // e.g., "Voice call" or "Missed voice call"
                        String statusOrDuration = callMatch.group(2)!.trim().replaceAll('‎', '').replaceAll(' ', ''); // Clean up hidden chars

                        if (callType == 'Voice call') {
                          callIcon = Icons.call;
                          displayMessageContent = statusOrDuration;
                        } else if (callType == 'Missed voice call') {
                          callIcon = Icons.call_missed;
                          if (statusOrDuration.toLowerCase().contains('tap to call back')) {
                            displayMessageContent = 'Missed';
                          } else {
                            displayMessageContent = statusOrDuration;
                          }
                        } else if (callType == 'Silenced voice call') {
                          callIcon = Icons.call_end;
                          if (statusOrDuration.toLowerCase().contains('focus mode')) {
                            displayMessageContent = 'Silenced (Focus Mode)';
                          } else {
                            displayMessageContent = statusOrDuration;
                          }
                        }
                      }

                      widgets.add(
                        GestureDetector( // Added GestureDetector for tap and double tap
                          onTap: () {
                            // Only allow tapping to open if it's an attachment
                            // Audio/Video files are now handled by _openAttachment, which directs to internal player
                            if (isAttachmentMessage) {
                              _openAttachment(message);
                            }
                            // No specific action for plain text messages on single tap
                          },
                          onDoubleTap: () => _copyMessageToClipboard(message),
                          child: Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: bubbleColor,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(15.0),
                                  topRight: const Radius.circular(15.0),
                                  bottomLeft: isMe ? const Radius.circular(15.0) : const Radius.circular(0.0),
                                  bottomRight: isMe ? const Radius.circular(0.0) : const Radius.circular(15.0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    spreadRadius: 1,
                                    blurRadius: 3,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.75),
                              child: Column(
                                crossAxisAlignment:
                                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.sender,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: secondaryTextColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4.0),
                                  // Display content based on message type
                                  if (message.mediaType == 'audio' && message.mediaFileName != null && _mediaFiles.containsKey(message.mediaFileName!))
                                    // Render the audio player widget
                                    AudioPlayerWidget(
                                      audioData: _mediaFiles[message.mediaFileName!]!,
                                      fileName: message.mediaFileName!,
                                      textColor: textColor,
                                      primaryColor: isMe ? Colors.white : Colors.teal.shade800, // Adjust primary color for audio player controls
                                    )
                                  else if (isAttachmentMessage) // Message with an attachment (non-audio)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (message.imageData != null) // Display image
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8.0),
                                            child: Image.memory(
                                              message.imageData!,
                                              fit: BoxFit.cover,
                                              width: 200, // Adjust width as needed
                                            ),
                                          )
                                        else if (message.mediaType == 'video') // Display video placeholder/icon
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.videocam,
                                                size: 20,
                                                color: textColor,
                                              ),
                                              const SizedBox(width: 8.0),
                                              Flexible(
                                                child: Text(
                                                  message.mediaFileName!,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: textColor,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          )
                                        else // Display document/other/missing media icon and filename
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                message.mediaType == 'document'
                                                    ? Icons.description
                                                    : message.mediaType == 'missing'
                                                        ? Icons.warning
                                                        : Icons.attach_file, // Generic attachment icon
                                                size: 20,
                                                color: message.mediaType == 'missing'
                                                        ? Colors.red
                                                        : textColor,
                                              ),
                                              const SizedBox(width: 8.0),
                                              Flexible(
                                                child: Text(
                                                  message.mediaType == 'missing'
                                                      ? 'Attachment not found: ${message.mediaFileName!}'
                                                      : message.mediaFileName!,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontStyle: message.mediaType == 'missing' ? FontStyle.italic : FontStyle.normal,
                                                    color: message.mediaType == 'missing'
                                                            ? Colors.red
                                                            : textColor,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        // Display additional text below attachment, if any
                                        // This part will use RichText if there's text with URLs
                                        if (message.parsedMessageParts.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8.0),
                                            child: RichText(
                                              text: TextSpan(
                                                children: message.parsedMessageParts.map((part) {
                                                  if (part.isLink) {
                                                    return TextSpan(
                                                      text: part.text,
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        color: isMe ? Colors.blue.shade200 : Colors.blue.shade800, // Link color
                                                        decoration: TextDecoration.underline,
                                                      ),
                                                      recognizer: TapGestureRecognizer()
                                                        ..onTap = () async {
                                                          if (part.url != null) {
                                                            final uri = Uri.parse(part.url!);
                                                            if (await canLaunchUrl(uri)) {
                                                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                                                            } else {
                                                              ScaffoldMessenger.of(context).showSnackBar(
                                                                SnackBar(content: Text('Could not open link: ${part.url}')),
                                                              );
                                                            }
                                                          }
                                                        },
                                                    );
                                                  } else {
                                                    return TextSpan(
                                                      text: part.text,
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        color: textColor,
                                                      ),
                                                    );
                                                  }
                                                }).toList(),
                                              ),
                                            ),
                                          ),
                                      ],
                                    )
                                  else if (isCallMessage) // If it's a recognized call message
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          callIcon,
                                          size: 20,
                                          color: textColor,
                                        ),
                                        const SizedBox(width: 8.0),
                                        Flexible(
                                          child: Text(
                                            displayMessageContent,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: textColor,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    )
                                  else // For all other messages (plain text or with detected links)
                                    RichText(
                                      text: TextSpan(
                                        children: message.parsedMessageParts.map((part) {
                                          if (part.isLink) {
                                            return TextSpan(
                                              text: part.text,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: isMe ? Colors.blue.shade200 : Colors.blue.shade800, // Link color
                                                decoration: TextDecoration.underline,
                                              ),
                                              recognizer: TapGestureRecognizer()
                                                ..onTap = () async {
                                                  if (part.url != null) {
                                                    final uri = Uri.parse(part.url!);
                                                    if (await canLaunchUrl(uri)) {
                                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                                    } else {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('Could not open link: ${part.url}')),
                                                      );
                                                    }
                                                  }
                                                },
                                            );
                                          } else {
                                            return TextSpan(
                                              text: part.text,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: textColor,
                                              ),
                                            );
                                          }
                                        }).toList(),
                                      ),
                                    ),
                                  const SizedBox(height: 4.0),
                                  Text(
                                    DateFormat('hh:mm a').format(message.timestamp),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMe ? Colors.white60 : Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return Column(children: widgets);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
