import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? webViewController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
  }

  void _showSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        if (webViewController != null) {
          if (await webViewController!.canGoBack()) {
            await webViewController!.goBack();
            return;
          }
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri('https://tailorbro.com')),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  transparentBackground: true,
                  useOnDownloadStart: true,
                  supportZoom: false, // disable zoom
                  builtInZoomControls: false,
                  displayZoomControls: false,
                  disableDefaultErrorPage: true,
                  shouldPrintBackgrounds: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                ),
                onConsoleMessage: (controller, consoleMessage) {
                  debugPrint("WebView Console: ${consoleMessage.message}");
                },
                onWebViewCreated: (controller) {
                  webViewController = controller;
                  
                  controller.addJavaScriptHandler(
                    handlerName: 'blobDownloadBase64',
                    callback: (args) async {
                      try {
                        String filename = args[0] as String;
                        String base64Data = args[1] as String;
                        
                        final bytes = base64Decode(base64Data);
                        Directory? dir;
                        if (Platform.isAndroid) {
                          dir = Directory('/storage/emulated/0/Download');
                          if (!await dir.exists()) {
                            dir = await getExternalStorageDirectory();
                          }
                        } else {
                          dir = await getApplicationDocumentsDirectory();
                        }
                        
                        final file = File('${dir!.path}/$filename');
                        await file.writeAsBytes(bytes);
                        _showSnackbar('File downloaded to: ${file.path}');
                      } catch (e) {
                        _showSnackbar('Download failed: $e');
                      }
                    },
                  );
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    _isLoading = true;
                  });
                },
                onLoadStop: (controller, url) async {
                  // Inject Javascript to force viewport scale to 1.0
                  await controller.evaluateJavascript(source: "if(document.querySelector('meta[name=\"viewport\"]')) { document.querySelector('meta[name=\"viewport\"]').setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=0'); } else { var meta = document.createElement('meta'); meta.name = 'viewport'; meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=0'; document.getElementsByTagName('head')[0].appendChild(meta); }");
                  
                  setState(() {
                    _isLoading = false;
                  });
                },
                onDownloadStartRequest: (controller, downloadRequest) async {
                  final url = downloadRequest.url.toString();
                  final filename = downloadRequest.suggestedFilename ?? 'downloaded_file';
                  
                  if (url.startsWith('blob:')) {
                    _showSnackbar('Downloading file...');
                    await controller.evaluateJavascript(source: '''
                      (async function() {
                        const response = await fetch("$url");
                        const blob = await response.blob();
                        const reader = new FileReader();
                        reader.onloadend = function() {
                          const base64data = reader.result.split(',')[1];
                          window.flutter_inappwebview.callHandler('blobDownloadBase64', '$filename', base64data);
                        };
                        reader.readAsDataURL(blob);
                      })();
                    ''');
                  } else {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final uri = navigationAction.request.url;
                  if (uri == null) return NavigationActionPolicy.ALLOW;

                  final url = uri.toString();
                  
                  // Intercept non-http(s) schemes like whatsapp:, tel:, mailto:, sms:
                  // Also intercept specific domains that should open in native apps (like WhatsApp)
                  if (!url.startsWith('http') || 
                      url.contains("wa.me") || 
                      url.contains("api.whatsapp.com")) {
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
                      return NavigationActionPolicy.CANCEL;
                    }
                  }
                  
                  return NavigationActionPolicy.ALLOW;
                },
                onPrintRequest: (controller, url, printJobController) async {
                  debugPrint("Print request received for: $url. Letting system handle it.");
                  return false;
                },
              ),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
