// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'globals.dart';
import 'primitives/auto_dispose.dart';
import 'primitives/utils.dart';

/// The page ID (used in routing) for the standalone app-size page.
///
/// This must be different to the AppSizeScreen ID which is also used in routing when
/// cnnected to a VM to ensure they have unique URLs.
const appSizePageId = 'appsize';

const homePageId = '';
const snapshotPageId = 'snapshot';

/// Represents a Page/route for a DevTools screen.
class DevToolsRouteConfiguration {
  DevToolsRouteConfiguration(this.page, this.args, this.state);

  final String page;
  final Map<String, String?> args;
  final DevToolsNavigationState? state;
}

/// Converts between structured [DevToolsRouteConfiguration] (our internal data
/// for pages/routing) and [RouteInformation] (generic data that can be persisted
/// in the address bar/state objects).
class DevToolsRouteInformationParser
    extends RouteInformationParser<DevToolsRouteConfiguration> {
  DevToolsRouteInformationParser();

  @visibleForTesting
  DevToolsRouteInformationParser.test(this._forceVmServiceUri);

  /// The value for the 'uri' query parameter in a DevTools uri.
  ///
  /// This is to be used in a testing environment only and can be set via the
  /// [DevToolsRouteInformationParser.test] constructor.
  String? _forceVmServiceUri;

  @override
  Future<DevToolsRouteConfiguration> parseRouteInformation(
    RouteInformation routeInformation,
  ) {
    var uri = Uri.parse(routeInformation.location!);

    if (_forceVmServiceUri != null) {
      final newQueryParams = Map<String, dynamic>.from(uri.queryParameters);
      newQueryParams['uri'] = _forceVmServiceUri;
      uri = uri.copyWith(queryParameters: newQueryParams);
    }

    // If the uri has been modified and we do not have a vm service uri as a
    // query parameter, ensure we manually disconnect from any previously
    // connected applications.
    if (uri.queryParameters['uri'] == null) {
      serviceManager.manuallyDisconnect();
    }

    // routeInformation.path comes from the address bar and (when not empty) is
    // prefixed with a leading slash. Internally we use "page IDs" that do not
    // start with slashes but match the screenId for each screen.
    final path = uri.path.isNotEmpty ? uri.path.substring(1) : '';
    final configuration = DevToolsRouteConfiguration(
      path,
      uri.queryParameters,
      routeInformation.state == null
          ? null
          : DevToolsNavigationState._(
              (routeInformation.state as Map).cast<String, String?>(),
            ),
    );
    return SynchronousFuture<DevToolsRouteConfiguration>(configuration);
  }

  @override
  RouteInformation restoreRouteInformation(
    DevToolsRouteConfiguration configuration,
  ) {
    // Add a leading slash to convert the page ID to a URL path (this is
    // the opposite of what's done in [parseRouteInformation]).
    final path = '/${configuration.page}';
    // Create a new map in case the one we were given was unmodifiable.
    final params = {...configuration.args};
    params.removeWhere((key, value) => value == null);
    return RouteInformation(
      location: Uri(
        path: path,
        queryParameters: params,
      ).toString(),
      state: configuration.state,
    );
  }
}

class DevToolsRouterDelegate extends RouterDelegate<DevToolsRouteConfiguration>
    with
        ChangeNotifier,
        PopNavigatorRouterDelegateMixin<DevToolsRouteConfiguration> {
  DevToolsRouterDelegate(this._getPage, [GlobalKey<NavigatorState>? key])
      : navigatorKey = key ?? GlobalKey<NavigatorState>();

  static DevToolsRouterDelegate of(BuildContext context) =>
      Router.of(context).routerDelegate as DevToolsRouterDelegate;

  @override
  final GlobalKey<NavigatorState> navigatorKey;

  final Page Function(
    BuildContext,
    String?,
    Map<String, String?>,
    DevToolsNavigationState?,
  ) _getPage;

  /// A list of any routes/pages on the stack.
  ///
  /// This will usually only contain a single item (it's the visible stack,
  /// not the history).
  final routes = ListQueue<DevToolsRouteConfiguration>();

  @override
  DevToolsRouteConfiguration? get currentConfiguration =>
      routes.isEmpty ? null : routes.last;

  @override
  Widget build(BuildContext context) {
    final routeConfig = currentConfiguration;
    final page = routeConfig?.page;
    final args = routeConfig?.args ?? {};
    final state = routeConfig?.state;

    return Navigator(
      key: navigatorKey,
      pages: [_getPage(context, page, args, state)],
      onPopPage: (_, __) {
        if (routes.length <= 1) {
          return false;
        }

        routes.removeLast();
        notifyListeners();
        return true;
      },
    );
  }

  /// Navigates to a new page, optionally updating arguments and state.
  ///
  /// If page, args, and state would be the same, does nothing.
  /// Existing arguments (for example &uri=) will be preserved unless
  /// overwritten by [argUpdates].
  void navigateIfNotCurrent(
    String page, [
    Map<String, String?>? argUpdates,
    DevToolsNavigationState? stateUpdates,
  ]) {
    final pageChanged = page != currentConfiguration!.page;
    final argsChanged = _changesArgs(argUpdates);
    final stateChanged = _changesState(stateUpdates);
    if (!pageChanged && !argsChanged && !stateChanged) {
      return;
    }

    navigate(page, argUpdates, stateUpdates);
  }

  /// Navigates to a new page, optionally updating arguments and state.
  ///
  /// Existing arguments (for example &uri=) will be preserved unless
  /// overwritten by [argUpdates].
  void navigate(
    String page, [
    Map<String, String?>? argUpdates,
    DevToolsNavigationState? state,
  ]) {
    final newArgs = {...currentConfiguration?.args ?? {}, ...?argUpdates};

    // Ensure we disconnect from any previously connected applications if we do
    // not have a vm service uri as a query parameter, unless we are loading an
    // offline file.
    if (page != snapshotPageId && newArgs['uri'] == null) {
      serviceManager.manuallyDisconnect();
    }

    _replaceStack(
      DevToolsRouteConfiguration(page, newArgs, state),
    );
    notifyListeners();
  }

  void navigateHome({
    bool clearUriParam = false,
    required bool clearScreenParam,
  }) {
    navigate(
      homePageId,
      {
        if (clearUriParam) 'uri': null,
        if (clearScreenParam) 'screen': null,
      },
    );
  }

  /// Replaces the navigation stack with a new route.
  void _replaceStack(DevToolsRouteConfiguration configuration) {
    routes
      ..clear()
      ..add(configuration);
  }

  @override
  Future<void> setNewRoutePath(DevToolsRouteConfiguration configuration) {
    _replaceStack(configuration);
    return SynchronousFuture<void>(null);
  }

  /// Updates arguments for the current page.
  ///
  /// Existing arguments (for example &uri=) will be preserved unless
  /// overwritten by [argUpdates].
  void updateArgsIfNotCurrent(Map<String, String> argUpdates) {
    final argsChanged = _changesArgs(argUpdates);
    if (!argsChanged) {
      return;
    }

    final currentConfig = currentConfiguration!;
    final currentPage = currentConfig.page;
    final newArgs = {...currentConfig.args, ...argUpdates};
    _replaceStack(
      DevToolsRouteConfiguration(
        currentPage,
        newArgs,
        currentConfig.state,
      ),
    );
    notifyListeners();
  }

  /// Checks whether applying [changes] over the current route's args will result
  /// in any changes.
  bool _changesArgs(Map<String, String?>? changes) {
    final currentConfig = currentConfiguration!;
    return !mapEquals(
      {...currentConfig.args, ...?changes},
      {...currentConfig.args},
    );
  }

  /// Checks whether applying [changes] over the current route's state will result
  /// in any changes.
  bool _changesState(DevToolsNavigationState? changes) {
    final currentState = currentConfiguration!.state;
    if (currentState == null) {
      return changes != null;
    }
    return currentState.hasChanges(changes);
  }
}

/// Encapsulates state associated with a [Router] navigation event.
class DevToolsNavigationState {
  DevToolsNavigationState({
    required this.kind,
    required Map<String, String?> state,
  }) : _state = {
          _kKind: kind,
          ...state,
        };

  factory DevToolsNavigationState.fromJson(Map<String, dynamic> json) =>
      DevToolsNavigationState._(json.cast<String, String?>());

  DevToolsNavigationState._(this._state) : kind = _state[_kKind]!;

  static const _kKind = '_kind';

  final String kind;

  UnmodifiableMapView<String, String?> get state => UnmodifiableMapView(_state);
  final Map<String, String?> _state;

  bool hasChanges(DevToolsNavigationState? other) {
    return !mapEquals(
      {...state, ...?other?.state},
      state,
    );
  }

  @override
  String toString() => _state.toString();

  Map<String, dynamic> toJson() => _state;
}

/// Mixin that gives controllers the ability to respond to changes in router
/// navigation state.
mixin RouteStateHandlerMixin on DisposableController {
  DevToolsRouterDelegate? _delegate;

  @override
  void dispose() {
    super.dispose();
    _delegate?.removeListener(_onRouteStateUpdate);
  }

  void subscribeToRouterEvents(DevToolsRouterDelegate delegate) {
    final oldDelegate = _delegate;
    if (oldDelegate != null) {
      oldDelegate.removeListener(_onRouteStateUpdate);
    }
    delegate.addListener(_onRouteStateUpdate);
    _delegate = delegate;
  }

  void _onRouteStateUpdate() {
    final state = _delegate?.currentConfiguration?.state;
    if (state == null) return;
    onRouteStateUpdate(state);
  }

  /// Perform operations based on changes in navigation state.
  ///
  /// This method is only invoked if [subscribeToRouterEvents] has been called on
  /// this instance with a valid [DevToolsRouterDelegate].
  void onRouteStateUpdate(DevToolsNavigationState state);
}
