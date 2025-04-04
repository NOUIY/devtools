// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vm_service/vm_service.dart';

import '../../connected_app.dart';
import '../../globals.dart';
import '../../primitives/auto_dispose.dart';
import '../../primitives/utils.dart';
import '../../theme.dart';
import '../../ui/search.dart';
import '../../ui/utils.dart';
import '../eval/eval_service.dart';
import '../primitives/eval_history.dart';

typedef AutoCompleteResultsFunction = Future<List<String>> Function(
  EditingParts parts,
  EvalService evalService,
);

class ExpressionEvalField extends StatefulWidget {
  const ExpressionEvalField({
    AutoCompleteResultsFunction? getAutoCompleteResults,
  }) : getAutoCompleteResults =
            getAutoCompleteResults ?? autoCompleteResultsFor;

  final AutoCompleteResultsFunction getAutoCompleteResults;

  @override
  ExpressionEvalFieldState createState() => ExpressionEvalFieldState();
}

class ExpressionEvalFieldState extends State<ExpressionEvalField>
    with AutoDisposeMixin, SearchFieldMixin {
  late AutoCompleteController _autoCompleteController;
  int historyPosition = -1;

  String _activeWord = '';
  List<String> _matches = [];

  final evalTextFieldKey = GlobalKey(debugLabel: 'evalTextFieldKey');

  @override
  void initState() {
    super.initState();

    serviceManager.consoleService.ensureServiceInitialized();

    _autoCompleteController = AutoCompleteController();

    addAutoDisposeListener(_autoCompleteController.searchNotifier, () {
      _autoCompleteController.handleAutoCompleteOverlay(
        context: context,
        searchFieldKey: evalTextFieldKey,
        onTap: _onSelection,
        bottom: false,
        maxWidth: false,
      );
    });
    addAutoDisposeListener(
      _autoCompleteController.selectTheSearchNotifier,
      _handleSearch,
    );
    addAutoDisposeListener(
      _autoCompleteController.searchNotifier,
      _handleSearch,
    );

    addAutoDisposeListener(
      _autoCompleteController.currentSuggestion,
      _handleSuggestionTextChange,
    );

    addAutoDisposeListener(
      _autoCompleteController.currentHoveredIndex,
      _handleHoverChange,
    );
  }

  bool _isRealVariableNameOrField(EditingParts parts) {
    return parts.activeWord.isNotEmpty || parts.isField;
  }

  void _handleHoverChange() {
    final editingParts = _currentEditingParts();

    if (!_isRealVariableNameOrField(editingParts)) {
      return;
    }

    _autoCompleteController.updateCurrentSuggestion(_activeWord);
  }

  EditingParts _currentEditingParts() {
    final searchingValue = _autoCompleteController.search;
    final isField = searchingValue.endsWith('.');

    final textFieldEditingValue = searchTextFieldController.value;
    final selection = textFieldEditingValue.selection;

    return AutoCompleteSearchControllerMixin.activeEditingParts(
      searchingValue,
      selection,
      handleFields: isField,
    );
  }

  void _handleSuggestionTextChange() {
    if (searchTextFieldController.isAtEnd) {
      // Only when the cursor is at the end of the text field, we update the
      // `suggestionText` displayed at the end of the text field.

      searchTextFieldController.suggestionText =
          _autoCompleteController.currentSuggestion.value;
    } else {
      searchTextFieldController.suggestionText = null;
    }
  }

  void _handleSearch() async {
    final searchingValue = _autoCompleteController.search;

    _autoCompleteController.clearCurrentSuggestion();

    if (searchingValue.isNotEmpty) {
      if (_autoCompleteController.selectTheSearch) {
        _autoCompleteController.resetSearch();
        return;
      }

      // We avoid clearing the list of possible matches here even though the
      // current matches may be out of date as clearing results in flicker
      // as Flutter will render a frame before the new matches are available.

      // Find word in TextField to try and match (word breaks).
      final parts = _currentEditingParts();

      // Only show pop-up if there's a real variable name or field.
      if (!_isRealVariableNameOrField(parts)) {
        _autoCompleteController.clearSearchAutoComplete();
        return;
      }

      // Update the current suggestion without waiting for the results to
      // to prevent flickering of the suggestion text.
      _autoCompleteController.updateCurrentSuggestion(parts.activeWord);

      final matches =
          parts.activeWord.startsWith(_activeWord) && _activeWord.isNotEmpty
              ? _filterMatches(_matches, parts.activeWord)
              : await widget.getAutoCompleteResults(parts, evalService);

      _matches = matches;
      _activeWord = parts.activeWord;

      if (matches.length == 1 && matches.first == parts.activeWord) {
        // It is not useful to show a single autocomplete that is exactly what
        // the already typed.
        _autoCompleteController.clearSearchAutoComplete();
        _autoCompleteController.clearCurrentSuggestion();
      } else {
        final results = matches
            .sublist(
              0,
              min(defaultTopMatchesLimit, matches.length),
            )
            .map((match) => AutoCompleteMatch(match))
            .toList();

        _autoCompleteController.searchAutoComplete.value = results;
        _autoCompleteController.setCurrentHoveredIndexValue(0);
        _autoCompleteController.updateCurrentSuggestion(parts.activeWord);
      }
    } else {
      _autoCompleteController.closeAutoCompleteOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('>'),
        const SizedBox(width: 8.0),
        Expanded(
          child: Focus(
            onKey: (_, RawKeyEvent event) {
              if (event.isKeyPressed(LogicalKeyboardKey.arrowUp)) {
                _historyNavUp();
                return KeyEventResult.handled;
              } else if (event.isKeyPressed(LogicalKeyboardKey.arrowDown)) {
                _historyNavDown();
                return KeyEventResult.handled;
              } else if (event.isKeyPressed(LogicalKeyboardKey.enter)) {
                _handleExpressionEval();
                return KeyEventResult.handled;
              }

              return KeyEventResult.ignored;
            },
            child: buildAutoCompleteSearchField(
              controller: _autoCompleteController,
              searchFieldKey: evalTextFieldKey,
              searchFieldEnabled: true,
              shouldRequestFocus: false,
              supportClearField: true,
              onSelection: _onSelection,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.all(denseSpacing),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide.none),
                labelText: 'Eval',
              ),
              overlayXPositionBuilder:
                  (String inputValue, TextStyle? inputStyle) {
                // X-coordinate is equivalent to the width of the input text
                // up to the last "." or the insertion point (cursor):
                final indexOfDot = inputValue.lastIndexOf('.');
                final textSegment = indexOfDot != -1
                    ? inputValue.substring(0, indexOfDot + 1)
                    : inputValue;
                return calculateTextSpanWidth(
                  TextSpan(
                    text: textSegment,
                    style: inputStyle,
                  ),
                );
              },
              // Disable ligatures, so the suggestions of the auto complete work correcly.
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontFeatures: [const FontFeature.disable('liga')]),
            ),
          ),
        ),
      ],
    );
  }

  void _onSelection(String word) {
    setState(() {
      _replaceActiveWord(word);
      _autoCompleteController.selectTheSearch = false;
      _autoCompleteController.closeAutoCompleteOverlay();
      _autoCompleteController.clearCurrentSuggestion();
    });
  }

  /// Replace the current activeWord (partial name) with the selected item from
  /// the auto-complete list.
  void _replaceActiveWord(String word) {
    final textFieldEditingValue = searchTextFieldController.value;
    final editingValue = textFieldEditingValue.text;
    final selection = textFieldEditingValue.selection;

    final parts = AutoCompleteSearchControllerMixin.activeEditingParts(
      editingValue,
      selection,
      handleFields: _autoCompleteController.search.endsWith('.'),
    );

    // Add the newly selected auto-complete value.
    final newValue = '${parts.leftSide}$word${parts.rightSide}';

    // Update the value and caret position of the auto-completed word.
    searchTextFieldController.value = TextEditingValue(
      text: newValue,
      selection: TextSelection.fromPosition(
        // Update the caret position to just beyond the newly picked
        // auto-complete item.
        TextPosition(offset: parts.leftSide.length + word.length),
      ),
    );
  }

  List<String> _filterMatches(
    List<String> previousMatches,
    String activeWord,
  ) {
    return previousMatches
        .where((match) => match.startsWith(activeWord))
        .toList();
  }

  void _handleExpressionEval() async {
    final expressionText = searchTextFieldController.value.text.trim();
    updateSearchField(newValue: '', caretPosition: 0);
    clearSearchField(_autoCompleteController, force: true);

    if (expressionText.isEmpty) return;

    // Only try to eval if we are paused.
    if (!serviceManager
        .isolateManager.mainIsolateDebuggerState!.isPaused.value!) {
      notificationService
          .push('Application must be paused to support expression evaluation.');
      return;
    }

    serviceManager.consoleService.appendStdio('> $expressionText\n');
    setState(() {
      historyPosition = -1;
      _appState.evalHistory.pushEvalHistory(expressionText);
    });

    try {
      // Response is either a ErrorRef, InstanceRef, or Sentinel.
      final isolateRef = serviceManager.isolateManager.selectedIsolate.value;
      final response = await evalService.evalAtCurrentFrame(expressionText);

      // Display the response to the user.
      if (response is InstanceRef) {
        _emitRefToConsole(response, isolateRef);
      } else {
        String? value = response.toString();

        if (response is ErrorRef) {
          value = response.message;
        } else if (response is Sentinel) {
          value = response.valueAsString;
        }

        _emitToConsole(value!);
      }
    } catch (e) {
      // Display the error to the user.
      _emitToConsole('$e');
    }
  }

  void _emitToConsole(String text) {
    serviceManager.consoleService.appendStdio(
      '  ${text.replaceAll('\n', '\n  ')}\n',
    );
  }

  void _emitRefToConsole(
    InstanceRef ref,
    IsolateRef? isolate,
  ) {
    serviceManager.consoleService.appendInstanceRef(
      value: ref,
      diagnostic: null,
      isolateRef: isolate,
      forceScrollIntoView: true,
    );
  }

  @override
  void dispose() {
    _autoCompleteController.dispose();
    super.dispose();
  }

  EvalHistory get _evalHistory => _appState.evalHistory;

  void _historyNavUp() {
    if (!_evalHistory.canNavigateUp) {
      return;
    }

    setState(() {
      _evalHistory.navigateUp();

      final text = _evalHistory.currentText ?? '';
      searchTextFieldController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  void _historyNavDown() {
    if (!_evalHistory.canNavigateDown) {
      return;
    }

    setState(() {
      _evalHistory.navigateDown();

      final text = _evalHistory.currentText ?? '';
      searchTextFieldController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }
}

AppState get _appState => serviceManager.appState;

Future<List<String>> autoCompleteResultsFor(
  EditingParts parts,
  EvalService evalService,
) async {
  final result = <String>{};
  if (!parts.isField) {
    final variables = _appState.variables.value;
    result.addAll(removeNullValues(variables.map((variable) => variable.name)));

    final thisVariable = variables.firstWhereOrNull(
      (variable) => variable.name == 'this',
    );
    if (thisVariable != null) {
      // If a variable named `this` is in scope, we should provide autocompletes
      // for all static and instance members of that class as they are in scope
      // in Dart. For example, if you evaluate `foo()` that will be equivalent
      // to `this.foo()` if foo is an instance member and `ThisClass.foo() if
      // foo is a static member.
      final thisValue = thisVariable.value;
      if (thisValue is InstanceRef) {
        await _addAllInstanceMembersToAutocompleteList(
          result,
          thisValue,
          evalService,
        );
        final classRef = thisValue.classRef;
        if (classRef != null) {
          result.addAll(
            await _autoCompleteMembersFor(
              classRef,
              evalService,
              staticContext: true,
            ),
          );
        }
      }
    }
    final frame = _appState.currentFrame.value;
    if (frame != null) {
      final function = frame.function;
      if (function != null) {
        final libraryRef = await evalService.findOwnerLibrary(function);
        if (libraryRef != null) {
          result.addAll(
            await libraryMemberAndImportsAutocompletes(
              libraryRef,
              evalService,
            ),
          );
        }
      }
    }
  } else {
    var left = parts.leftSide.split(' ').last;
    // Removing trailing `.`.
    left = left.substring(0, left.length - 1);
    try {
      final response = await evalService.evalAtCurrentFrame(left);
      if (response is InstanceRef) {
        final typeClass = response.typeClass;
        if (typeClass != null) {
          // Assume we want static members for a type class not members of the
          // Type object. This is reasonable as Type objects are rarely useful
          // in Dart and we will end up with accidental Type objects if the user
          // writes `SomeClass.` in the evaluate window.
          result.addAll(
            await _autoCompleteMembersFor(
              typeClass,
              evalService,
              staticContext: true,
            ),
          );
        } else {
          await _addAllInstanceMembersToAutocompleteList(
            result,
            response,
            evalService,
          );
        }
      }
    } catch (_) {}
  }
  return removeNullValues(result)
      .where((name) => name.startsWith(parts.activeWord))
      .toList();
}

// Due to https://github.com/dart-lang/sdk/issues/46221
// we cannot tell what the show clause for an export was so it is unsafe to
// surface exports as if they were library members as there tend to be
// significant false positives for libraries such as Flutter where all of
// dart:ui shows up as in scope from flutter:foundation when it should not be.
bool debugIncludeExports = true;

Future<Set<String>> libraryMemberAndImportsAutocompletes(
  LibraryRef libraryRef,
  EvalService evalService,
) async {
  final values = removeNullValues(
    await _appState.cache.libraryMemberAndImportsAutocomplete.putIfAbsent(
      libraryRef,
      () => _libraryMemberAndImportsAutocompletes(libraryRef, evalService),
    ),
  );
  return values.toSet();
}

Future<Set<String>> _libraryMemberAndImportsAutocompletes(
  LibraryRef libraryRef,
  EvalService evalService,
) async {
  final result = <String>{};
  try {
    final List<Future<Set<String>>> futures = <Future<Set<String>>>[];
    futures.add(
      libraryMemberAutocompletes(
        evalService,
        libraryRef,
        includePrivates: true,
      ),
    );

    final Library library = await evalService.getObject(libraryRef) as Library;
    final dependencies = library.dependencies;

    if (dependencies != null) {
      for (var dependency in library.dependencies!) {
        final prefix = dependency.prefix;
        final target = dependency.target;
        if (prefix != null && prefix.isNotEmpty) {
          // We won't give a list of autocompletes once you enter a prefix
          // but at least we do include the prefix in the autocompletes list.
          result.add(prefix);
        } else if (target != null) {
          futures.add(
            libraryMemberAutocompletes(
              evalService,
              target,
              includePrivates: false,
            ),
          );
        }
      }
    }
    (await Future.wait(futures)).forEach(result.addAll);
  } catch (_) {
    // Silently skip library completions if there is a failure.
  }
  return result;
}

Future<Set<String>> libraryMemberAutocompletes(
  EvalService evalService,
  LibraryRef libraryRef, {
  required bool includePrivates,
}) async {
  var result = removeNullValues(
    await _appState.cache.libraryMemberAutocomplete.putIfAbsent(
      libraryRef,
      () => _libraryMemberAutocompletes(evalService, libraryRef),
    ),
  );
  if (!includePrivates) {
    result = result.where((name) => !isPrivate(name));
  }
  return result.toSet();
}

Future<Set<String>> _libraryMemberAutocompletes(
  EvalService evalService,
  LibraryRef libraryRef,
) async {
  final result = <String>{};
  final Library library = await evalService.getObject(libraryRef) as Library;
  final variables = library.variables;
  if (variables != null) {
    final fields = variables.map((field) => field.name);
    result.addAll(removeNullValues(fields));
  }
  final functions = library.functions;
  if (functions != null) {
    // The VM shows setters as `<member>=`.
    final members =
        functions.map((funcRef) => funcRef.name!.replaceAll('=', ''));
    result.addAll(removeNullValues(members));
  }
  final classes = library.classes;
  if (classes != null) {
    // Autocomplete class names as well
    final classNames = classes.map((clazz) => clazz.name);
    result.addAll(removeNullValues(classNames));
  }

  if (debugIncludeExports) {
    final List<Future<Set<String>>> futures = <Future<Set<String>>>[];
    for (var dependency in library.dependencies!) {
      if (!dependency.isImport!) {
        final prefix = dependency.prefix;
        final target = dependency.target;
        if (prefix != null && prefix.isNotEmpty) {
          result.add(prefix);
        } else if (target != null) {
          futures.add(
            libraryMemberAutocompletes(
              evalService,
              target,
              includePrivates: false,
            ),
          );
        }
      }
    }
    if (futures.isNotEmpty) {
      (await Future.wait(futures)).forEach(result.addAll);
    }
  }
  return result;
}

Future<void> _addAllInstanceMembersToAutocompleteList(
  Set<String> result,
  InstanceRef response,
  EvalService controller,
) async {
  final Instance instance = await controller.getObject(response) as Instance;
  final classRef = instance.classRef;
  if (classRef == null) return;
  result.addAll(
    await _autoCompleteMembersFor(
      classRef,
      controller,
      staticContext: false,
    ),
  );
  // TODO(grouma) - This shouldn't be necessary but package:dwds does
  // not properly provide superclass information.
  final fields = instance.fields;
  if (fields == null) return;
  final clazz = await controller.classFor(classRef);
  final fieldNames = fields
      .where((field) => field.decl?.isStatic != null && !field.decl!.isStatic!)
      .map((field) => field.decl?.name);
  result.addAll(
    removeNullValues(fieldNames).where(
      (member) => _isAccessible(member, clazz, controller),
    ),
  );
}

Future<Set<String>> _autoCompleteMembersFor(
  ClassRef classRef,
  EvalService controller, {
  required bool staticContext,
}) async {
  final result = <String>{};
  final clazz = await controller.classFor(classRef);
  if (clazz != null) {
    final fields = clazz.fields;
    if (fields != null) {
      final fieldNames = fields
          .where((f) => f.isStatic == staticContext)
          .map((field) => field.name);
      result.addAll(removeNullValues(fieldNames));
    }

    final functions = clazz.functions;
    if (functions != null) {
      for (var funcRef in functions) {
        if (_validFunction(funcRef, clazz, staticContext)) {
          final isConstructor = _isConstructor(funcRef, clazz);
          final funcName = funcRef.name;
          if (funcName == null) continue;
          // The VM shows setters as `<member>=`.
          var name = funcName.replaceAll('=', '');
          if (isConstructor) {
            final clazzName = clazz.name!;
            assert(name.startsWith(clazzName));
            if (name.length <= clazzName.length + 1) continue;
            name = name.substring(clazzName.length + 1);
          }
          result.add(name);
        }
      }
    }
    final superClass = clazz.superClass;
    if (!staticContext && superClass != null) {
      result.addAll(
        await _autoCompleteMembersFor(
          superClass,
          controller,
          staticContext: staticContext,
        ),
      );
    }
    result.removeWhere((member) => !_isAccessible(member, clazz, controller));
  }
  return result;
}

bool _validFunction(FuncRef funcRef, Class clazz, bool staticContext) {
  // TODO(jacobr): we should include named constructors in static contexts.
  return ((_isConstructor(funcRef, clazz) || funcRef.isStatic!) ==
          staticContext) &&
      !_isOperator(funcRef);
}

bool _isOperator(FuncRef funcRef) => const {
      '==',
      '+',
      '-',
      '*',
      '/',
      '&',
      '~',
      '|',
      '>',
      '<',
      '>=',
      '<=',
      '>>',
      '<<',
      '>>>',
      '^',
      '%',
      '~/',
      'unary-',
    }.contains(funcRef.name);

bool _isConstructor(FuncRef funcRef, Class clazz) =>
    funcRef.name == clazz.name || funcRef.name!.startsWith('${clazz.name}.');

bool _isAccessible(
  String member,
  Class? clazz,
  EvalService evalService,
) {
  final frame = _appState.currentFrame.value!;
  final currentScript = frame.location!.script;
  return !isPrivate(member) || currentScript!.id == clazz?.location?.script?.id;
}
