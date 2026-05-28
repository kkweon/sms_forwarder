import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'file_logger.dart';

class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key, required this.logger});

  final FileLogger logger;

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  String _logContent = '';
  String _buildInfo = 'Loading build info…';
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _loadBuildInfo();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final content = await widget.logger.readAll();
    if (!mounted) return;
    setState(
      () => _logContent = content.isEmpty ? '(no log entries yet)' : content,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _loadBuildInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final mode = kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : kDebugMode
          ? 'debug'
          : 'unknown';
      final lines = [
        'App:      ${info.appName} (${info.packageName})',
        'Version:  ${info.version}+${info.buildNumber}',
        'Build:    $mode',
        if (info.buildSignature.isNotEmpty) 'Signature: ${info.buildSignature}',
        if (info.installerStore != null) 'Installer: ${info.installerStore}',
      ];
      if (!mounted) return;
      setState(() => _buildInfo = lines.join('\n'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _buildInfo = 'Could not read build info: $e');
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _clear() async {
    await widget.logger.clear();
    if (!mounted) return;
    setState(() => _logContent = '(log cleared)');
  }

  void _copyAll() {
    Clipboard.setData(ClipboardData(text: '$_buildInfo\n\n$_logContent'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Build info + log copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Log'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SelectableText(
              _buildInfo,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _logContent,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
