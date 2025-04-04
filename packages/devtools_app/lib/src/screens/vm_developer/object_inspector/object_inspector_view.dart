// Copyright 2022 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/analytics/constants.dart' as gac;
import '../../../shared/split.dart';
import '../../../shared/ui/tab.dart';
import '../../debugger/program_explorer.dart';
import '../../debugger/program_explorer_model.dart';
import '../vm_developer_tools_controller.dart';
import '../vm_developer_tools_screen.dart';
import 'object_inspector_view_controller.dart';
import 'object_store.dart';
import 'object_viewport.dart';

/// Displays a program explorer and a history viewport that displays
/// information about objects in the Dart VM.
class ObjectInspectorView extends VMDeveloperView {
  ObjectInspectorView()
      : super(
          id,
          title: 'Objects',
          icon: Icons.data_object_outlined,
        );
  static const id = 'object-inspector-view';

  @override
  bool get showIsolateSelector => true;

  @override
  Widget build(BuildContext context) => _ObjectInspectorView();
}

class _ObjectInspectorView extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _ObjectInspectorViewState();
}

class _ObjectInspectorViewState extends State<_ObjectInspectorView>
    with TickerProviderStateMixin {
  late ObjectInspectorViewController controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vmDeveloperToolsController =
        Provider.of<VMDeveloperToolsController>(context);
    controller = vmDeveloperToolsController.objectInspectorViewController
      ..init();
  }

  @override
  Widget build(BuildContext context) {
    return Split(
      axis: Axis.horizontal,
      initialFractions: const [0.2, 0.8],
      children: [
        AnalyticsTabbedView(
          gaScreen: gac.objectInspectorScreen,
          tabs: [
            DevToolsTab.create(
              tabName: 'Program Explorer',
              gaPrefix: gac.programExplorer,
            ),
            DevToolsTab.create(
              tabName: 'Object Store',
              gaPrefix: gac.objectStore,
            ),
          ],
          tabViews: [
            ProgramExplorer(
              controller: controller.programExplorerController,
              onNodeSelected: _onNodeSelected,
              displayHeader: false,
            ),
            ObjectStoreViewer(
              controller: controller.objectStoreController,
              onLinkTapped: controller.findAndSelectNodeForObject,
            ),
          ],
        ),
        ObjectViewport(
          controller: controller,
        ),
      ],
    );
  }

  void _onNodeSelected(VMServiceObjectNode node) {
    final objRef = node.object;
    final location = node.location;
    if (objRef != null &&
        objRef != controller.objectHistory.current.value?.ref) {
      unawaited(controller.pushObject(objRef, scriptRef: location?.scriptRef));
    }
  }
}
