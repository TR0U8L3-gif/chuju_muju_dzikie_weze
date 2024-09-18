import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

const maxIterationsToRefreshToken = 3;

Future<void> main(List<String> arguments) async {
  io.stdin.echoMode = false;
  io.stdin.lineMode = false;

  StreamSubscription? subscription;
  final tokenManager = TokenManager();

  subscription = io.stdin.listen((List<int> codes) {
    if (codes.first == 0x08) {
      subscription?.cancel();
      return;
    }

    tokenManager.refreshToken(codes);

    print('Codes: $codes, ${utf8.decode(codes)}');
  });

  print('Program started');
}

class TokenManager {
  static final TokenManager _instance = TokenManager._internal();

  factory TokenManager() {
    return _instance;
  }

  TokenManager._internal() {
    _setupStreams();
  }

  // fake token refresh time
  var fakeTokenRefreshTime = DateTime.now().millisecondsSinceEpoch;

  var refreshTokenQueue = 0;
  var refreshTokenInstance = 0;
  var refreshTokenFailedAttempts = 0;

  StreamController<RefreshTokenRequest>? _refreshRequestStream;
  StreamController<RefreshTokenResponse>? _refreshResponseStream;
  Completer<bool>? _refreshingTokenCompleter; // check if token is refreshing

  //to do - implement refresh token with timeout and completer
  Future<RefreshTokenResponse> refreshToken(List<int> codes) async {

    print('refreshToken Codes: $codes, Queue: $refreshTokenQueue');
    _refreshRequestStream!.add(RefreshTokenRequest(codes: codes));

    final response = await _refreshResponseStream!.stream.first;

    if (response.failure != null) {
      refreshTokenFailedAttempts++;
      print('[FAILED] refreshToken Failed: ${response.failure!.message}, Attempts: $refreshTokenFailedAttempts, Codes: $codes, ${utf8.decode(codes)}');

    } else {
      refreshTokenFailedAttempts = 0;
      print('refreshToken Success: ${response.success!.message} Codes: $codes, ${utf8.decode(codes)}');
    }

    //todo implement handling other attempts
    
    return response;
  }

  void _setupStreams() {
    if (_refreshRequestStream != null) {
      _refreshRequestStream!.close();
      print('[SETUP] REQUEST: Closing previous request stream');
    }
    _refreshRequestStream = StreamController<RefreshTokenRequest>.broadcast();
    print('[SETUP] REQUEST: Created new request stream');

    if (_refreshResponseStream != null) {
      _refreshResponseStream!.close();
      print('[SETUP] RESPONSE: Closing previous response stream');
    }
    _refreshResponseStream = StreamController<RefreshTokenResponse>.broadcast();
    print('[SETUP] RESPONSE: Created new response stream');

    _listenToRefreshResponse();

    _listenToRefreshRequest();
  }

  void _listenToRefreshResponse() {
    print('[SETUP] RESPONSE: Listening to refresh response');

    _refreshResponseStream!.stream.listen(
      (_) {
        print('[RESPONSE STREAM] New refresh response received');
      },
      onDone: () {
        print('[RESPONSE STREAM] Refresh response stream closed');
      },
      onError: (Object error, StackTrace stackTrace) {
        print('[RESPONSE STREAM] Error on refresh response stream: $error');
      },
      cancelOnError: false,
    );
  }

  Future<void> _listenToRefreshRequest() async {
    print('[SETUP] REQUEST: Listening to refresh request');

    _refreshRequestStream!.stream.listen(
      (_) {
        refreshTokenQueue++;
        print('[REQUEST STREAM] New refresh request received');
      },
      onDone: () {
        print('[REQUEST STREAM] Refresh request stream closed');
      },
      onError: (Object error, StackTrace stackTrace) {
        print('[REQUEST STREAM] Error on refresh request stream: $error');
      },
      cancelOnError: false,
    );

    await for (final request in _refreshRequestStream!.stream) {
      print('[REQUEST SYNC STREAM] Request: $request');
      await _refreshTokenRequest(request);
    }
  }

  Future<void> _refreshTokenRequest(RefreshTokenRequest request) async {
    print(
        '[REFRESH TOKEN REQUEST] Request: $request, ($refreshTokenInstance|$refreshTokenQueue)');
    final isExpired = await _checkIfTokenIsExpired();
    if (isExpired) {
      print('[REFRESH TOKEN REQUEST] Token is expired');
      final isRefreshing = _checkIfTokenIsRefreshing();
      if (isRefreshing) {
        print('[REFRESH TOKEN REQUEST] Token is refreshing');
        refreshTokenQueue--;
      } else {
        print('[REFRESH TOKEN REQUEST] Token is not refreshing');
        _refreshingTokenCompleter = Completer<bool>();
        _refreshToken().then((state) {
          TokenResponse response;
          switch (state) {
            case TokenState.fresh:
                response = TokenSuccess(
                  message: 'Token is fresh',
                  state: TokenState.fresh,
                );
            case TokenState.refreshed:
              response = TokenSuccess(
                message: 'Token refreshed',
                state: TokenState.refreshed,
              );
            case TokenState.timeout:
              response = TokenFailure(
                message: 'Token refresh timeout',
                state: TokenState.timeout,
              );
            case TokenState.error:
              response = TokenFailure(
                message: 'Token refresh failed',
                state: TokenState.error,
              );
          }

          _refreshResponseStream!.add(
            RefreshTokenResponse.fromResponse(response),
          );

          _refreshingTokenCompleter?.complete(true);
          refreshTokenQueue--;
        });
      }
    } else {
      print('[REFRESH TOKEN REQUEST] Token is not expired');
      _refreshResponseStream!.add(
        RefreshTokenResponse.success(
          success: TokenSuccess(
            message: 'Token is not expired',
            state: TokenState.fresh,
          ),
        ),
      );
      refreshTokenQueue--;
    }
  }

  Future<bool> _checkIfTokenIsExpired() async {
    // delay to read token
    await Future.delayed(Duration(milliseconds: 100));

    final now = DateTime.now().millisecondsSinceEpoch;
    final offset = 1000 * 30;
    final diff = now - fakeTokenRefreshTime;

    print(
        '[CHECK IF EXPIRED] offset: $offset, diff: $diff now: ${DateTime.fromMillisecondsSinceEpoch(now)}, fakeTokenRefreshTime: ${DateTime.fromMillisecondsSinceEpoch(fakeTokenRefreshTime)}');

    if (diff <= offset) {
      return false;
    } else {
      return true;
    }
  }

  bool _checkIfTokenIsRefreshing() {
    if (_refreshingTokenCompleter != null &&
        !_refreshingTokenCompleter!.isCompleted) {
      return true;
    } else {
      return false;
    }
  }

  Future<TokenState> _refreshToken() async {
    refreshTokenInstance++;
    print('[REFRESH TOKEN] Refreshing token started, Instance: $refreshTokenInstance');
    print('[REFRESH TOKEN] ask api for new token...' );
    await Future.delayed(Duration(seconds: 15));
    final now = DateTime.now().millisecondsSinceEpoch;
    fakeTokenRefreshTime = now;
    print('[REFRESH TOKEN] Token refreshed at ${DateTime.fromMillisecondsSinceEpoch(now)}');
    refreshTokenInstance--;
    print('[REFRESH TOKEN] Refreshing token ended, Instance: $refreshTokenInstance');
    return TokenState.refreshed;
  }
}

class RefreshTokenRequest {
  RefreshTokenRequest({required this.codes});
  final List<int> codes;
}

class RefreshTokenResponse {
  RefreshTokenResponse._({required this.success, required this.failure})
      : assert(success != null || failure != null,
            'Either success or failure must be provided');

  factory RefreshTokenResponse.success({required TokenSuccess success}) {
    return RefreshTokenResponse._(success: success, failure: null);
  }

  factory RefreshTokenResponse.failure({required TokenFailure failure}) {
    return RefreshTokenResponse._(success: null, failure: failure);
  }

  factory RefreshTokenResponse.fromResponse(TokenResponse response) {
    if (response is TokenSuccess) {
      return RefreshTokenResponse.success(success: response);
    } else if (response is TokenFailure) {
      return RefreshTokenResponse.failure(failure: response);
    } else {
      return RefreshTokenResponse.failure(failure: TokenFailure(
        message: 'RefreshTokenResponse.fromResponse: Unknown response type',
        state: TokenState.error,
      ));
    }
  }

  final TokenSuccess? success;
  final TokenFailure? failure;

  TokenResponse fold({
    required TokenSuccess Function(TokenSuccess success) onSuccess,
    required TokenFailure Function(TokenFailure failure) onFailure,
  }) {
    return success != null ? onSuccess(success!) : onFailure(failure!);
  }
}

abstract class TokenResponse {
  TokenResponse({required this.message, required this.state});
  final String message;
  final TokenState state;
}

class TokenFailure extends TokenResponse {
  TokenFailure(
      {required super.message,
      required super.state,
      this.error,
      this.stackTrace});

  final Object? error;
  final StackTrace? stackTrace;
}

class TokenSuccess extends TokenResponse {
  TokenSuccess({required super.message, required super.state});
}

enum TokenState {
  fresh,
  refreshed,
  timeout,
  error,
}
