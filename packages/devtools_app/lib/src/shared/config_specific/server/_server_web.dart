// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found
// in the LICENSE file.

import 'dart:async';
import 'dart:convert';
// TODO(jacobr): this should use package:http instead of dart:html.
import 'dart:html';

import 'package:devtools_shared/devtools_shared.dart';

import '../../primitives/utils.dart';
import '../logger/logger.dart';

// Code to check if DevTools server is available, will only be true in release
// mode, debug mode will be set to false.
bool get isDevToolsServerAvailable => !isDebugBuild();

/// Helper to catch any server request which could fail.
///
/// Returns HttpRequest or null (if server failure).
Future<HttpRequest?> request(String url) async {
  HttpRequest? response;

  try {
    response = await HttpRequest.request(url, method: 'POST');
  } catch (_) {}

  return response;
}

/// Request DevTools property value 'firstRun' (GA dialog) stored in the file
/// '~/flutter-devtools/.devtools'.
Future<bool> isFirstRun() async {
  bool firstRun = false;

  if (isDevToolsServerAvailable) {
    final resp = await request(apiGetDevToolsFirstRun);
    if (resp?.status == HttpStatus.ok) {
      firstRun = json.decode(resp!.responseText!);
    } else {
      logWarning(resp, apiGetDevToolsFirstRun);
    }
  }

  return firstRun;
}

/// Request DevTools property value 'enabled' (GA enabled) stored in the file
/// '~/.flutter-devtools/.devtools'.
Future<bool> isAnalyticsEnabled() async {
  bool enabled = false;
  if (isDevToolsServerAvailable) {
    final resp = await request(apiGetDevToolsEnabled);
    if (resp?.status == HttpStatus.ok) {
      enabled = json.decode(resp!.responseText!);
    } else {
      logWarning(resp, apiGetDevToolsEnabled);
    }
  }
  return enabled;
}

/// Set the DevTools property 'enabled' (GA enabled) stored in the file
/// '~/.flutter-devtools/.devtools'.
///
/// Returns whether the set call was successful.
Future<bool> setAnalyticsEnabled([bool value = true]) async {
  if (isDevToolsServerAvailable) {
    final resp = await request(
      '$apiSetDevToolsEnabled'
      '?$devToolsEnabledPropertyName=$value',
    );
    if (resp?.status == HttpStatus.ok) {
      assert(json.decode(resp!.responseText!) == value);
      return true;
    } else {
      logWarning(resp, apiSetDevToolsEnabled, resp?.responseText);
    }
  }
  return false;
}

// TODO(terry): Move to an API scheme similar to the VM service extension where
// '/api/devToolsEnabled' returns the value (identical VM service) and
// '/api/devToolsEnabled?value=true' sets the value.

/// Request Flutter tool stored property value enabled (GA enabled) stored in
/// the file '~\.flutter'.
///
/// Return bool.
/// Return value of false implies either GA is disabled or the Flutter Tool has
/// never been run (null returned from the server).
Future<bool> _isFlutterGAEnabled() async {
  bool enabled = false;

  if (isDevToolsServerAvailable) {
    final resp = await request(apiGetFlutterGAEnabled);
    if (resp?.status == HttpStatus.ok) {
      // A return value of 'null' implies Flutter tool has never been run so
      // return false for Flutter GA enabled.
      final responseValue = json.decode(resp!.responseText!);
      enabled = responseValue == null ? false : responseValue;
    } else {
      logWarning(resp, apiGetFlutterGAEnabled);
    }
  }

  return enabled;
}

/// Request Flutter tool stored property value clientID (GA enabled) stored in
/// the file '~\.flutter'.
///
/// Return as a String, empty string implies Flutter Tool has never been run.
Future<String> flutterGAClientID() async {
  // Default empty string, Flutter tool never run.
  String clientId = '';

  if (isDevToolsServerAvailable) {
    // Test if Flutter is enabled (or if Flutter Tool ever ran) if not enabled
    // is false, we don't want to be the first to create a ~/.flutter file.
    if (await _isFlutterGAEnabled()) {
      final resp = await request(apiGetFlutterGAClientId);
      if (resp?.status == HttpStatus.ok) {
        clientId = json.decode(resp!.responseText!);
        if (clientId.isEmpty) {
          // Requested value of 'null' (Flutter tool never ran). Server request
          // apiGetFlutterGAClientId should not happen because the
          // isFlutterGAEnabled test should have been false.
          log('$apiGetFlutterGAClientId is empty', LogLevel.warning);
        }
      } else {
        logWarning(resp, apiGetFlutterGAClientId);
      }
    }
  }

  return clientId;
}

/// Set DevTools parameter value for the active survey (e.g. 'Q1-2020').
///
/// The value is stored in the file '~/.flutter-devtools/.devtools'.
///
/// This method must be called before calling other survey related methods
/// ([isSurveyActionTaken], [setSurveyActionTaken], [surveyShownCount],
/// [incrementSurveyShownCount]). If the active survey is not set, warnings are
/// logged.
Future<bool> setActiveSurvey(String value) async {
  if (isDevToolsServerAvailable) {
    final resp = await request(
      '$apiSetActiveSurvey'
      '?$activeSurveyName=$value',
    );
    if (resp?.status == HttpStatus.ok && json.decode(resp!.responseText!)) {
      return true;
    } else {
      logWarning(resp, apiSetActiveSurvey);
    }
  }
  return false;
}

/// Request DevTools property value 'surveyActionTaken' for the active survey.
///
/// The value is stored in the file '~/.flutter-devtools/.devtools'.
///
/// Requires [setActiveSurvey] to have been called prior to calling this method.
Future<bool> surveyActionTaken() async {
  bool surveyActionTaken = false;

  if (isDevToolsServerAvailable) {
    final resp = await request(apiGetSurveyActionTaken);
    if (resp?.status == HttpStatus.ok) {
      surveyActionTaken = json.decode(resp!.responseText!);
    } else {
      logWarning(resp, apiGetSurveyActionTaken);
    }
  }

  return surveyActionTaken;
}

/// Set DevTools property value 'surveyActionTaken' for the active survey.
///
/// The value is stored in the file '~/.flutter-devtools/.devtools'.
///
/// Requires [setActiveSurvey] to have been called prior to calling this method.
Future<void> setSurveyActionTaken() async {
  if (isDevToolsServerAvailable) {
    final resp = await request(
      '$apiSetSurveyActionTaken'
      '?$surveyActionTakenPropertyName=true',
    );
    if (resp?.status != HttpStatus.ok || !json.decode(resp!.responseText!)) {
      logWarning(resp, apiSetSurveyActionTaken, resp?.responseText);
    }
  }
}

/// Request DevTools property value 'surveyShownCount' for the active survey.
///
/// The value is stored in the file '~/.flutter-devtools/.devtools'.
///
/// Requires [setActiveSurvey] to have been called prior to calling this method.
Future<int> surveyShownCount() async {
  int surveyShownCount = 0;

  if (isDevToolsServerAvailable) {
    final resp = await request(apiGetSurveyShownCount);
    if (resp?.status == HttpStatus.ok) {
      surveyShownCount = json.decode(resp!.responseText!);
    } else {
      logWarning(resp, apiGetSurveyShownCount);
    }
  }

  return surveyShownCount;
}

/// Increment DevTools property value 'surveyShownCount' for the active survey.
///
/// The value is stored in the file '~/.flutter-devtools/.devtools'.
///
/// Requires [setActiveSurvey] to have been called prior to calling this method.
Future<int> incrementSurveyShownCount() async {
  // Any failure will still return 0.
  int surveyShownCount = 0;

  if (isDevToolsServerAvailable) {
    final resp = await request(apiIncrementSurveyShownCount);
    if (resp?.status == HttpStatus.ok) {
      surveyShownCount = json.decode(resp!.responseText!);
    } else {
      logWarning(resp, apiIncrementSurveyShownCount);
    }
  }
  return surveyShownCount;
}

/// Requests the DevTools version for which we last showed release notes.
///
/// This value is stored in the file '~/.flutter-devtools/.devtools'.
Future<String> getLastShownReleaseNotesVersion() async {
  String version = '';
  if (isDevToolsServerAvailable) {
    final resp = await request(apiGetLastReleaseNotesVersion);
    if (resp?.status == HttpStatus.ok) {
      version = json.decode(resp!.responseText!);
    } else {
      logWarning(resp, apiGetLastReleaseNotesVersion);
    }
  }
  return version;
}

/// Sets the DevTools version for which we last showed release notes.
///
/// This value is stored in the file '~/.flutter-devtools/.devtools'.
Future<void> setLastShownReleaseNotesVersion(String version) async {
  if (isDevToolsServerAvailable) {
    final resp = await request(
      '$apiSetLastReleaseNotesVersion'
      '?$lastReleaseNotesVersionPropertyName=$version',
    );
    if (resp == null ||
        resp.status != HttpStatus.ok ||
        !json.decode(resp.responseText!)) {
      logWarning(resp, apiSetLastReleaseNotesVersion, resp?.responseText);
    }
  }
}

/// Requests all .devtools properties to be reset to their default values in the
/// file '~/.flutter-devtools/.devtools'.
Future<void> resetDevToolsFile() async {
  if (isDevToolsServerAvailable) {
    final resp = await request(apiResetDevTools);
    if (resp?.status == HttpStatus.ok) {
      assert(json.decode(resp!.responseText!));
    } else {
      logWarning(resp, apiResetDevTools);
    }
  }
}

Future<DevToolsJsonFile?> requestBaseAppSizeFile(String path) {
  return requestFile(
    api: apiGetBaseAppSizeFile,
    fileKey: baseAppSizeFilePropertyName,
    filePath: path,
  );
}

Future<DevToolsJsonFile?> requestTestAppSizeFile(String path) {
  return requestFile(
    api: apiGetTestAppSizeFile,
    fileKey: testAppSizeFilePropertyName,
    filePath: path,
  );
}

Future<DevToolsJsonFile?> requestFile({
  required String api,
  required String fileKey,
  required String filePath,
}) async {
  if (isDevToolsServerAvailable) {
    final url = Uri(path: api, queryParameters: {fileKey: filePath});
    final resp = await request(url.toString());
    if (resp?.status == HttpStatus.ok) {
      return _devToolsJsonFileFromResponse(resp!, filePath);
    } else {
      logWarning(resp, api);
    }
  }
  return null;
}

DevToolsJsonFile _devToolsJsonFileFromResponse(
  HttpRequest resp,
  String filePath,
) {
  final data = json.decode(resp.response);
  final lastModified = data['lastModifiedTime'];
  final lastModifiedTime =
      lastModified != null ? DateTime.parse(lastModified) : DateTime.now();
  return DevToolsJsonFile(
    name: filePath,
    lastModifiedTime: lastModifiedTime,
    data: data,
  );
}

void logWarning(HttpRequest? response, String apiType, [String? respText]) {
  log(
    'HttpRequest $apiType failed status = ${response?.status}'
    '${respText != null ? ', responseText = $respText' : ''}',
    LogLevel.warning,
  );
}
