// Copyright 2022 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart' hide Stack;

import '../../../shared/object_tree.dart';
import '../../../shared/primitives/listenable.dart';
import '../../../shared/tree.dart';
import 'display_provider.dart';

class ExpandableVariable extends StatelessWidget {
  const ExpandableVariable({
    Key? key,
    this.variable,
  }) : super(key: key);

  @visibleForTesting
  static const emptyExpandableVariableKey = Key('empty expandable variable');

  final DartObjectNode? variable;

  @override
  Widget build(BuildContext context) {
    final variable = this.variable;
    if (variable == null)
      return const SizedBox(key: emptyExpandableVariableKey);
    // TODO(kenz): preserve expanded state of tree on switching frames and
    // on stepping.
    return TreeView<DartObjectNode>(
      dataRootsListenable:
          FixedValueListenable<List<DartObjectNode>>([variable]),
      shrinkWrap: true,
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
