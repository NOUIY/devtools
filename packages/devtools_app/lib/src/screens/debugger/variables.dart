// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// TODO(https://github.com/flutter/devtools/issues/4717): migrate away from
// deprecated members.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart' hide Stack;

import '../../shared/console/widgets/display_provider.dart';
import '../../shared/globals.dart';
import '../../shared/object_tree.dart';
import '../../shared/tree.dart';

class Variables extends StatelessWidget {
  const Variables({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // TODO(kenz): preserve expanded state of tree on switching frames and
    // on stepping.
    return TreeView<DartObjectNode>(
      dataRootsListenable: serviceManager.appState.variables,
      dataDisplayProvider: (variable, onPressed) => DisplayProvider(
        variable: variable,
        onTap: onPressed,
      ),
      onItemSelected: onItemPressed,
    );
  }

  Future<void> onItemPressed(
    DartObjectNode v,
  ) async {
    // On expansion, lazily build the variables tree for performance reasons.
    if (v.isExpanded) {
      await Future.wait(v.children.map(buildVariablesTree));
    }
  }
}
