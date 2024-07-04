import 'package:flutter/material.dart';
import 'package:linkedin_auth/src/models/models.dart';
import 'package:linkedin_auth/src/service/linkedin_service.dart';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;

class LinkedInLoginView extends StatefulWidget {
  final String redirectUrl;
  final String clientId;
  final String clientSecret;
  final bool bypassServerCheck;
  final Function(String) onError;
  final Function(AccessToken) onTokenCapture;
  final AccessToken Function(http.Response) onServerResponse;
  final List<LinkedInScope>? scopes;

  LinkedInLoginView({
    required this.redirectUrl,
    required this.clientId,
    required this.onError,
    this.clientSecret = "",
    this.bypassServerCheck = false,
    required this.onTokenCapture,
    required this.onServerResponse,
    this.scopes,
  });

  _LinkedInLoginViewState createState() => _LinkedInLoginViewState();
}

class _LinkedInLoginViewState extends State<LinkedInLoginView> {
  static const _LINKEDIN_CODE = "code";
  static const _LINKEDIN_STATE = "state";
  static const _LINKEDIN_ERROR = "error";
  static const _LINKEDIN_ERROR_DESC = "error_description";
  late LinkedInRequest _request;
  late final WebViewController _controller;

  @override
  void dispose() {
    super.dispose();
    final cookieManager = WebViewCookieManager();
    cookieManager.clearCookies();
  }

  @override
  void initState() {
    super.initState();
    List<LinkedInScope> scopelist = [
      LinkedInScope.EMAIL_ADDRESS,
      LinkedInScope.LITE_PROFILE
    ];
    _request = LinkedInService.getLinkedInRequest(
      clientId: widget.clientId,
      redirectUri: widget.redirectUrl,
      scopes: widget.scopes ?? scopelist,
    );

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest req) {
            return _navDelegate(req);
          },
        ),
      )
      ..loadRequest(Uri.parse(_request.url));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }

  NavigationDecision _navDelegate(NavigationRequest req) {
    if (req.url.contains(widget.redirectUrl)) {
      Uri uri = Uri.parse(req.url);
      Map<String, String> params = uri.queryParameters;
      String error = _parseError(params);
      if (error.isNotEmpty) {
        widget.onError(error);
        return NavigationDecision.prevent;
      }
      if (params.containsKey(_LINKEDIN_STATE) &&
          !_request.verifyState(params[_LINKEDIN_STATE]!)) {
        widget.onError("State match failed, possible CSRF issue");
        return NavigationDecision.prevent;
      }
      if (params.containsKey(_LINKEDIN_CODE) && widget.bypassServerCheck) {
        _getToken(params[_LINKEDIN_CODE]!);
      } else {
        _getServerData(req.url);
        return NavigationDecision.prevent;
      }
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _getServerData(String url) async {
    var res = await http.get(Uri.parse(url));
    var token = widget.onServerResponse(res);
    widget.onTokenCapture(token);
  }

  Future<void> _getToken(String code) async {
    try {
      var token = await LinkedInService.generateToken(
        clientId: widget.clientId,
        clientSecret: widget.clientSecret,
        code: code,
        redirectUri: widget.redirectUrl,
      );
      widget.onTokenCapture(token);
    } catch (e) {
      widget.onError(e.toString());
    }
  }

  String _parseError(Map<String, String> params) {
    if (params.containsKey(_LINKEDIN_ERROR)) {
      return params[_LINKEDIN_ERROR_DESC]!;
    }
    return "";
  }
}
