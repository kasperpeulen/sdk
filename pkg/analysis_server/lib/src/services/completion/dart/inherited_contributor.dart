// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library services.completion.dart.invocation;

import 'dart:async';

import 'package:analysis_server/src/protocol_server.dart'
    show CompletionSuggestion, CompletionSuggestionKind, SourceChange;
import 'package:analysis_server/src/protocol_server.dart' as protocol
    hide CompletionSuggestion, CompletionSuggestionKind;
import 'package:analysis_server/src/provisional/completion/completion_core.dart';
import 'package:analysis_server/src/provisional/completion/dart/completion_dart.dart';
import 'package:analysis_server/src/provisional/completion/dart/completion_target.dart';
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/source.dart';

/**
 * A completion contributor used to suggest replacing partial identifiers inside
 * a class declaration with templates for inherited members.
 */
class InheritedContributor implements DartCompletionContributor {
  @override
  Future<List<CompletionSuggestion>> computeSuggestions(
      DartCompletionRequest request) async {
    // Determine if the target looks like a partial identifier
    // inside a class declaration
    SimpleIdentifier targetId = _getTargetId(request.target);
    if (targetId == null) {
      return EMPTY_LIST;
    }

    // Partially resolve the compilation unit
    CompilationUnit unit = await request.resolveDeclarationsInScope();
    // Gracefully degrade if the compilation unit could not be resolved
    // e.g. detached part file or source change
    if (unit == null) {
      return EMPTY_LIST;
    }

    // Recompute the target since resolution may have changed it
    targetId = _getTargetId(request.target);
    if (targetId == null) {
      return EMPTY_LIST;
    }
    ClassDeclaration classDecl =
        targetId.getAncestor((p) => p is ClassDeclaration);
    if (classDecl == null) {
      return EMPTY_LIST;
    }

    // Generate a collection of inherited members
    ClassElement classElem = classDecl.element;
    InheritanceManager manager = new InheritanceManager(classElem.library);
    MemberMap map = manager.getMapOfMembersInheritedFromInterfaces(classElem);
    List<String> memberNames = _computeMemberNames(map, classElem);

    // Build suggestions
    List<CompletionSuggestion> suggestions = <CompletionSuggestion>[];
    for (String memberName in memberNames) {
      ExecutableElement element = map.get(memberName);
      // Gracefully degrade if the overridden element has not been resolved.
      if (element.returnType != null) {
        CompletionSuggestion suggestion =
            _buildSuggestion(request, targetId, unit, element);
        if (suggestion != null) {
          suggestions.add(suggestion);
        }
      }
    }
    return suggestions;
  }

  /**
   * If the target looks like a partial identifier inside a class declaration
   * then return that identifier, otherwise return `null`.
   */
  SimpleIdentifier _getTargetId(CompletionTarget target) {
    AstNode node = target.containingNode;
    if (node is ClassDeclaration) {
      Object entity = target.entity;
      if (entity is FieldDeclaration) {
        NodeList<VariableDeclaration> variables = entity.fields.variables;
        if (variables.length == 1) {
          SimpleIdentifier targetId = variables[0].name;
          if (targetId.name.isEmpty) {
            return targetId;
          }
        }
      }
    }
    return null;
  }

  /**
   * Return a template for an override of the given [element] in the given
   * [source]. If selected, the template will replace [targetId].
   */
  String _buildRepacementText(Source source, SimpleIdentifier targetId,
      CompilationUnit unit, ExecutableElement element) {
    // AnalysisContext context = element.context;
    // Inject partially resolved unit for use by change builder
    // DartChangeBuilder builder = new DartChangeBuilder(context, unit);
    // builder.addFileEdit(source, context.getModificationStamp(source),
    //     (DartFileEditBuilder builder) {
    //   builder.addReplacement(targetId.offset, targetId.length,
    //       (DartEditBuilder builder) {
    //     builder.writeOverrideOfInheritedMember(element);
    //   });
    // });
    // return builder.sourceChange.edits[0].edits[0].replacement.trim();
    return '';
  }

  /**
   * Build a suggestion to replace [targetId] in the given [unit]
   * with an override of the given [element].
   */
  CompletionSuggestion _buildSuggestion(
      DartCompletionRequest request,
      SimpleIdentifier targetId,
      CompilationUnit unit,
      ExecutableElement element) {
    String completion =
        _buildRepacementText(request.source, targetId, unit, element);
    if (completion == null || completion.length == 0) {
      return null;
    }
    CompletionSuggestion suggestion = new CompletionSuggestion(
        CompletionSuggestionKind.IDENTIFIER,
        DART_RELEVANCE_HIGH,
        completion,
        targetId.offset,
        0,
        element.isDeprecated,
        false);
    suggestion.element = protocol.convertElement(element);
    return suggestion;
  }

  /**
   * Return a list containing the names of all of the inherited but not
   * implemented members of the class represented by the given [element].
   * The [map] is used to find all of the members that are inherited.
   */
  List<String> _computeMemberNames(MemberMap map, ClassElement element) {
    List<String> memberNames = <String>[];
    int count = map.size;
    for (int i = 0; i < count; i++) {
      String memberName = map.getKey(i);
      if (!_hasMember(element, memberName)) {
        memberNames.add(memberName);
      }
    }
    return memberNames;
  }

  /**
   * Return `true` if the given [classElement] directly declares a member with
   * the given [memberName].
   */
  bool _hasMember(ClassElement classElement, String memberName) {
    return classElement.getField(memberName) != null ||
        classElement.getGetter(memberName) != null ||
        classElement.getMethod(memberName) != null ||
        classElement.getSetter(memberName) != null;
  }
}
