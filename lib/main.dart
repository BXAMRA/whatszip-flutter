import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
// Import the characters package for better emoji handling (grapheme clusters)
import 'package:flutter/services.dart'; // Import for Clipboard
import 'dart:convert'; // Import for utf8.decode

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // This will build a Material app for android and a Cupertino app for iOS
    if (Platform.isIOS) {
      return const CupertinoApp(
        title: 'WhatsZip Viewer',
        theme: CupertinoThemeData(primaryColor: CupertinoColors.systemGreen),
        home: ChatScreen(),
        debugShowCheckedModeBanner: false,
      );
    } else {
      return MaterialApp(
        title: 'WhatsZip Viewer',
        theme: ThemeData(
          primarySwatch: Colors.green,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const ChatScreen(),
        debugShowCheckedModeBanner: false,
      );
    }
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<ChatMessage> _messages = [];
  String? _chatTitle;
  bool _isLoading = false;
  Map<String, File> _mediaFiles = {};
  String? _currentUser;

  Future<void> _pickAndProcessZip() async {
    setState(() {
      _isLoading = true;
      _messages = [];
      _mediaFiles = {};
      _chatTitle = null;
      _currentUser = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        final inputStream = InputFileStream(file.path);
        final archive = ZipDecoder().decodeBuffer(inputStream);
        final tempDir = await getTemporaryDirectory();

        ArchiveFile? chatFile;
        for (final file in archive) {
          if (file.name.endsWith('_chat.txt')) {
            chatFile = file;
          } else if (file.isFile) {
            final extractedFile = File('${tempDir.path}/${file.name}');
            await extractedFile.writeAsBytes(file.content as List<int>);
            _mediaFiles[file.name] = extractedFile;
          }
        }

        if (chatFile == null) {
          final archiveFiles = archive.files
              .where((file) => file.name.contains('WhatsApp Chat'))
              .toList();
          if (archiveFiles.isNotEmpty) {
            chatFile = archiveFiles.first;
          }
        }

        if (chatFile != null) {
          // Explicitly decode chat content as UTF-8 to handle emojis correctly
          final chatContent = utf8.decode(chatFile.content as List<int>);
          await _parseChatContent(chatContent);
          final chatFileName = chatFile.name.split('/').last;
          _chatTitle = chatFileName
              .replaceAll('_chat.txt', '')
              .replaceAll('WhatsApp Chat with ', '')
              .trim();
        } else {
          _showErrorDialog("No '_chat.txt' file found in the zip archive.");
        }
      }
    } catch (e) {
      _showErrorDialog("Failed to process zip file: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectCurrentUser(List<String> participants) async {
    if (Platform.isIOS) {
      // Use CupertinoActionSheet for iOS
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (BuildContext context) => CupertinoActionSheet(
          title: const Text('Select Your Name'),
          actions: participants
              .map(
                (p) => CupertinoActionSheetAction(
                  child: Text(p),
                  onPressed: () {
                    setState(() {
                      _currentUser = p;
                    });
                    Navigator.pop(context);
                  },
                ),
              )
              .toList(),
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
        ),
      );
    } else {
      // Use Material AlertDialog for Android
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Select Your Name'),
            content: SingleChildScrollView(
              child: ListBody(
                children: participants
                    .map(
                      (p) => RadioListTile<String>(
                        title: Text(p),
                        value: p,
                        groupValue: _currentUser,
                        onChanged: (String? value) {
                          setState(() {
                            _currentUser = value;
                          });
                          Navigator.of(context).pop();
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        },
      );
    }
  }

  Future<void> _parseChatContent(String content) async {
    // Remove the invisible Unicode characters LRM (U+200E) and RLM (U+200F) before parsing
    // WhatsApp chat exports sometimes contain these, which can appear as 'â€Ž' or 'â€¯'
    final cleanedContent = content
        .replaceAll('\u200E', '')
        .replaceAll('\u200F', '');
    final lines = cleanedContent.split('\n');
    final messages = <ChatMessage>[];
    final participants = <String>{};
    final regex = RegExp(r'^\[([^\]]+)\] ([^:]+): (.*)');
    // Updated regex to work on the cleaned string
    final mediaRegex = RegExp(r'^(.*?)<attached: (.*?)>');

    for (final line in lines) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final timestamp = match.group(1)!;
        final sender = match.group(2)!;
        final messageText = match.group(3)!.trim();

        participants.add(sender);

        final mediaMatch = mediaRegex.firstMatch(messageText);

        if (mediaMatch != null) {
          final caption = mediaMatch.group(1)!.trim();
          final fileName = mediaMatch.group(2)!.trim();
          messages.add(
            ChatMessage(
              sender: sender,
              timestamp: timestamp,
              text: caption.isNotEmpty ? caption : fileName,
              mediaPath: fileName,
            ),
          );
        } else {
          // Use characters.whereType<String>() to ensure proper handling of emoji grapheme clusters
          messages.add(
            ChatMessage(
              sender: sender,
              timestamp: timestamp,
              text: messageText,
            ),
          );
        }
      }
    }

    if (participants.isNotEmpty) {
      // Let the user select their name from the participants
      await _selectCurrentUser(participants.toList());
    }

    setState(() {
      _messages = messages;
    });
  }

  void _showErrorDialog(String message) {
    if (Platform.isIOS) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // New method to copy message content
  void _copyMessageContent(ChatMessage message) {
    final String contentToCopy =
        '[${message.timestamp}] ${message.sender}: ${message.text.characters.whereType<String>().join()}';

    Clipboard.setData(ClipboardData(text: contentToCopy)).then((_) {
      if (Platform.isIOS) {
        showCupertinoModalPopup(
          context: context,
          builder: (BuildContext context) => CupertinoActionSheet(
            title: const Text('Copied to Clipboard'),
            message: Text(
              '"${contentToCopy.characters.take(50).join()}..."',
            ), // Show first 50 chars
            actions: [
              CupertinoActionSheetAction(
                isDefaultAction: true,
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Message copied to clipboard!'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Widget _buildMessage(ChatMessage message) {
    final isMe = message.sender == _currentUser;
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final color = isMe
        ? (Platform.isIOS
              ? CupertinoColors.systemGreen.withOpacity(0.7)
              : Colors.lightGreen[100])
        : (Platform.isIOS ? CupertinoColors.white : Colors.white);
    final textColor = isMe ? Colors.white : Colors.black87;

    return GestureDetector(
      // Wrap the Card with GestureDetector
      onDoubleTap: () => _copyMessageContent(message),
      child: Container(
        alignment: alignment,
        child: Card(
          color: color,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Removed the sender's name display
                // if (!isMe)
                //   Text(
                //     message.sender,
                //     style: TextStyle(
                //         fontWeight: FontWeight.bold,
                //         color: Platform.isIOS ? CupertinoColors.systemGreen : Theme.of(context).primaryColor),
                //   ),
                if (message.mediaPath != null &&
                    _mediaFiles.containsKey(message.mediaPath))
                  _buildMediaPreview(
                    _mediaFiles[message.mediaPath]!,
                    message.text,
                  ),
                // Use characters.whereType<String>().join() for text display to ensure proper emoji rendering
                if (message.mediaPath == null ||
                    !_mediaFiles.containsKey(message.mediaPath))
                  Text(
                    message.text.characters
                        .whereType<String>()
                        .join(), // Apply characters here
                    style: TextStyle(
                      color: isMe ? Colors.black87 : textColor,
                      fontSize: 16,
                    ),
                  ),
                const SizedBox(height: 5),
                Text(
                  message.timestamp,
                  style: TextStyle(color: Colors.grey[600], fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaPreview(File mediaFile, String caption) {
    final extension = mediaFile.path.split('.').last.toLowerCase();

    return GestureDetector(
      onTap: () async {
        try {
          await OpenFile.open(mediaFile.path);
        } catch (e) {
          _showErrorDialog("Could not open file: $e");
        }
      },
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (['jpg', 'jpeg', 'png', 'gif'].contains(extension))
              ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: Image.file(mediaFile, fit: BoxFit.cover),
              )
            else if (extension == 'pdf')
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[100]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Platform.isIOS
                          ? CupertinoIcons.doc_fill
                          : Icons.picture_as_pdf,
                      color: Colors.red,
                      size: 40,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        caption.characters
                            .whereType<String>()
                            .join(), // Apply characters here
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Platform.isIOS
                          ? CupertinoIcons.doc_text_fill
                          : Icons.insert_drive_file,
                      color: Colors.grey[700],
                      size: 40,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        caption.characters
                            .whereType<String>()
                            .join(), // Apply characters here
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            if (caption.isNotEmpty &&
                !caption.endsWith(extension) &&
                !['jpg', 'jpeg', 'png', 'gif'].contains(extension)) ...[
              const SizedBox(height: 8),
              Text(
                caption.characters.whereType<String>().join(),
              ), // Apply characters here
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: NetworkImage(
            "https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png",
          ),
          fit: BoxFit.cover,
        ),
      ),
      child: _isLoading
          ? Center(
              child: Platform.isIOS
                  ? const CupertinoActivityIndicator()
                  : const CircularProgressIndicator(),
            )
          : _messages.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Platform.isIOS ? CupertinoIcons.chat_bubble_2 : Icons.chat,
                    size: 100,
                    color: Colors.green.withOpacity(0.7),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Select a WhatsApp chat zip file to begin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.grey[800]),
                  ),
                  const SizedBox(height: 20),
                  if (Platform.isIOS)
                    CupertinoButton.filled(
                      onPressed: _pickAndProcessZip,
                      child: const Text('Select ZIP'),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _pickAndProcessZip,
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Select ZIP'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                ],
              ),
            )
          : ListView.builder(
              reverse: false,
              padding: const EdgeInsets.all(10.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) => _buildMessage(_messages[index]),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text('WhatsZip Viewer'),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            child: const Icon(CupertinoIcons.folder_open),
            onPressed: _pickAndProcessZip,
          ),
        ),
        child: SafeArea(child: _buildBody()),
      );
    } else {
      return Scaffold(
        appBar: AppBar(
          title: Text('WhatsZip Viewer'),
          actions: [
            IconButton(
              icon: const Icon(Icons.file_upload),
              onPressed: _pickAndProcessZip,
              tooltip: 'Open Chat Archive',
            ),
          ],
        ),
        body: SafeArea(child: _buildBody()),
      );
    }
  }
}

class ChatMessage {
  final String sender;
  final String timestamp;
  final String text;
  final String? mediaPath;

  ChatMessage({
    required this.sender,
    required this.timestamp,
    required this.text,
    this.mediaPath,
  });
}
