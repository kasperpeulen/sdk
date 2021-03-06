// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analysis_server.src.provisional.completion.dart.plugin;

import 'package:analysis_server/src/provisional/completion/dart/completion.dart';
import 'package:analysis_server/src/provisional/completion/dart/completion_dart.dart';
import 'package:analysis_server/src/services/completion/dart/keyword_contributor.dart';
import 'package:plugin/plugin.dart';

/**
 * The shared dart completion plugin instance.
 */
final DartCompletionPlugin dartCompletionPlugin = new DartCompletionPlugin();

class DartCompletionPlugin implements Plugin {
  /**
   * The simple identifier of the extension point that allows plugins to
   * register Dart specific completion contributor factories.
   * Use [DART_COMPLETION_CONTRIBUTOR_EXTENSION_POINT_ID]
   * when registering contributors.
   */
  static const String CONTRIBUTOR_EXTENSION_POINT = 'contributor';

  /**
   * The unique identifier of this plugin.
   */
  static const String UNIQUE_IDENTIFIER = 'dart.completion';

  /**
   * The extension point that allows plugins to register Dart specific
   * completion contributor factories.
   */
  ExtensionPoint _contributorExtensionPoint;

  @override
  String get uniqueIdentifier => UNIQUE_IDENTIFIER;

  /**
   * Return a list containing all of the Dart specific completion contributor
   * factories that were contributed.
   */
  List<DartCompletionContributorFactory> get contributorFactories =>
      _contributorExtensionPoint.extensions;

  @override
  void registerExtensionPoints(RegisterExtensionPoint registerExtensionPoint) {
    _contributorExtensionPoint = registerExtensionPoint(
        CONTRIBUTOR_EXTENSION_POINT,
        _validateDartCompletionContributorExtension);
  }

  @override
  void registerExtensions(RegisterExtension registerExtension) {
    registerExtension(DART_COMPLETION_CONTRIBUTOR_EXTENSION_POINT_ID,
        () => new KeywordContributor());
  }

  /**
   * Validate the given extension by throwing an [ExtensionError] if it is not a
   * valid Dart specific completion contributor.
   */
  void _validateDartCompletionContributorExtension(Object extension) {
    if (extension is! DartCompletionContributorFactory) {
      String id = _contributorExtensionPoint.uniqueIdentifier;
      throw new ExtensionError(
          'Extensions to $id must be a DartCompletionContributorFactory');
    }
  }
}
