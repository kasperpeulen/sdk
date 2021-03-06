// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file

// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library services.completion.dart.keyword;

import 'dart:async';

import 'package:analysis_server/plugin/protocol/protocol.dart';
import 'package:analysis_server/src/provisional/completion/dart/completion_dart.dart';
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/scanner.dart';

const ASYNC = 'async';
const AWAIT = 'await';

/**
 * A contributor for calculating `completion.getSuggestions` request results
 * for the local library in which the completion is requested.
 */
class KeywordContributor extends DartCompletionContributor {
  @override
  Future<List<CompletionSuggestion>> computeSuggestions(
      DartCompletionRequest request) async {
    if (request.target.isCommentText) {
      return EMPTY_LIST;
    }
    List<CompletionSuggestion> suggestions = <CompletionSuggestion>[];
    request.target.containingNode
        .accept(new _KeywordVisitor(request, suggestions));
    return suggestions;
  }
}

/**
 * A visitor for generating keyword suggestions.
 */
class _KeywordVisitor extends GeneralizingAstVisitor {
  final DartCompletionRequest request;
  final Object entity;
  final List<CompletionSuggestion> suggestions;

  _KeywordVisitor(DartCompletionRequest request, this.suggestions)
      : this.request = request,
        this.entity = request.target.entity;

  @override
  visitArgumentList(ArgumentList node) {
    if (entity == node.rightParenthesis ||
        (entity is SimpleIdentifier && node.arguments.contains(entity))) {
      _addExpressionKeywords(node);
    }
  }

  @override
  visitBlock(Block node) {
    if (entity is ExpressionStatement) {
      Expression expression = (entity as ExpressionStatement).expression;
      if (expression is SimpleIdentifier) {
        Token token = expression.token;
        Token previous = token.previous;
        if (previous.isSynthetic) {
          previous = previous.previous;
        }
        Token next = token.next;
        if (next.isSynthetic) {
          next = next.next;
        }
        if (previous.lexeme == ')' && next.lexeme == '{') {
          _addSuggestion2(ASYNC);
        }
      }
    }
    _addStatementKeywords(node);
    if (_inCatchClause(node)) {
      _addSuggestion(Keyword.RETHROW, DART_RELEVANCE_KEYWORD - 1);
    }
  }

  @override
  visitClassDeclaration(ClassDeclaration node) {
    // Don't suggest class name
    if (entity == node.name) {
      return;
    }
    if (entity == node.rightBracket) {
      _addClassBodyKeywords();
    } else if (entity is ClassMember) {
      _addClassBodyKeywords();
      int index = node.members.indexOf(entity);
      ClassMember previous = index > 0 ? node.members[index - 1] : null;
      if (previous is MethodDeclaration && previous.body is EmptyFunctionBody) {
        _addSuggestion2(ASYNC);
      }
    } else {
      _addClassDeclarationKeywords(node);
    }
  }

  @override
  visitCompilationUnit(CompilationUnit node) {
    var previousMember = null;
    for (var member in node.childEntities) {
      if (entity == member) {
        break;
      }
      previousMember = member;
    }
    if (previousMember is ClassDeclaration) {
      if (previousMember.leftBracket == null ||
          previousMember.leftBracket.isSynthetic) {
        // If the prior member is an unfinished class declaration
        // then the user is probably finishing that
        _addClassDeclarationKeywords(previousMember);
        return;
      }
    }
    if (previousMember is ImportDirective) {
      if (previousMember.semicolon == null ||
          previousMember.semicolon.isSynthetic) {
        // If the prior member is an unfinished import directive
        // then the user is probably finishing that
        _addImportDirectiveKeywords(previousMember);
        return;
      }
    }
    if (previousMember == null || previousMember is Directive) {
      if (previousMember == null &&
          !node.directives.any((d) => d is LibraryDirective)) {
        _addSuggestions([Keyword.LIBRARY], DART_RELEVANCE_HIGH);
      }
      _addSuggestions(
          [Keyword.IMPORT, Keyword.EXPORT, Keyword.PART], DART_RELEVANCE_HIGH);
    }
    if (entity == null || entity is Declaration) {
      if (previousMember is FunctionDeclaration &&
          previousMember.functionExpression is FunctionExpression &&
          previousMember.functionExpression.body is EmptyFunctionBody) {
        _addSuggestion2(ASYNC, relevance: DART_RELEVANCE_HIGH);
      }
      _addCompilationUnitKeywords();
    }
  }

  @override
  visitExpression(Expression node) {
    _addExpressionKeywords(node);
  }

  @override
  visitExpressionFunctionBody(ExpressionFunctionBody node) {
    if (entity == node.expression) {
      _addExpressionKeywords(node);
    }
  }

  @override
  visitForEachStatement(ForEachStatement node) {
    if (entity == node.inKeyword) {
      Token previous = node.inKeyword.previous;
      if (previous is SyntheticStringToken && previous.lexeme == 'in') {
        previous = previous.previous;
      }
      if (previous != null && previous.type == TokenType.EQ) {
        _addSuggestions([
          Keyword.CONST,
          Keyword.FALSE,
          Keyword.NEW,
          Keyword.NULL,
          Keyword.TRUE
        ]);
      } else {
        _addSuggestion(Keyword.IN, DART_RELEVANCE_HIGH);
      }
    }
  }

  @override
  visitFormalParameterList(FormalParameterList node) {
    AstNode constructorDeclaration =
        node.getAncestor((p) => p is ConstructorDeclaration);
    if (constructorDeclaration != null) {
      _addSuggestions([Keyword.THIS]);
    }
  }

  @override
  visitForStatement(ForStatement node) {
    // Handle the degenerate case while typing - for (int x i^)
    if (node.condition == entity && entity is SimpleIdentifier) {
      Token entityToken = (entity as SimpleIdentifier).beginToken;
      if (entityToken.previous.isSynthetic &&
          entityToken.previous.type == TokenType.SEMICOLON) {
        _addSuggestion(Keyword.IN, DART_RELEVANCE_HIGH);
      }
    }
  }

  @override
  visitFunctionExpression(FunctionExpression node) {
    if (entity == node.body) {
      if (!node.body.isAsynchronous) {
        _addSuggestion2(ASYNC, relevance: DART_RELEVANCE_HIGH);
      }
      if (node.body is EmptyFunctionBody &&
          node.parent is FunctionDeclaration &&
          node.parent.parent is CompilationUnit) {
        _addCompilationUnitKeywords();
      }
    }
  }

  @override
  visitIfStatement(IfStatement node) {
    if (entity == node.thenStatement) {
      _addStatementKeywords(node);
    } else if (entity == node.condition) {
      _addExpressionKeywords(node);
    }
  }

  @override
  visitImportDirective(ImportDirective node) {
    if (entity == node.asKeyword) {
      if (node.deferredKeyword == null) {
        _addSuggestion(Keyword.DEFERRED, DART_RELEVANCE_HIGH);
      }
    }
    // Handle degenerate case where import statement does not have a semicolon
    // and the cursor is in the uri string
    if ((entity == node.semicolon &&
            node.uri != null &&
            node.uri.offset + 1 != request.offset) ||
        node.combinators.contains(entity)) {
      _addImportDirectiveKeywords(node);
    }
  }

  @override
  visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (entity == node.constructorName) {
      // no keywords in 'new ^' expression
    } else {
      super.visitInstanceCreationExpression(node);
    }
  }

  @override
  visitIsExpression(IsExpression node) {
    if (entity == node.isOperator) {
      _addSuggestion(Keyword.IS, DART_RELEVANCE_HIGH);
    } else {
      _addExpressionKeywords(node);
    }
  }

  @override
  visitLibraryIdentifier(LibraryIdentifier node) {
    // no suggestions
  }

  @override
  visitMethodDeclaration(MethodDeclaration node) {
    if (entity == node.body) {
      if (node.body is EmptyFunctionBody) {
        _addClassBodyKeywords();
        _addSuggestion2(ASYNC);
      } else {
        _addSuggestion2(ASYNC, relevance: DART_RELEVANCE_HIGH);
      }
    }
  }

  @override
  visitMethodInvocation(MethodInvocation node) {
    if (entity == node.methodName) {
      // no keywords in '.' expression
    } else {
      super.visitMethodInvocation(node);
    }
  }

  @override
  visitNamedExpression(NamedExpression node) {
    if (entity is SimpleIdentifier && entity == node.expression) {
      _addExpressionKeywords(node);
    }
  }

  @override
  visitNode(AstNode node) {
    // ignored
  }

  @override
  visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (entity != node.identifier) {
      _addExpressionKeywords(node);
    }
  }

  @override
  visitPropertyAccess(PropertyAccess node) {
    // suggestions before '.' but not after
    if (entity != node.propertyName) {
      super.visitPropertyAccess(node);
    }
  }

  @override
  visitReturnStatement(ReturnStatement node) {
    if (entity == node.expression) {
      _addExpressionKeywords(node);
    }
  }

  @override
  visitStringLiteral(StringLiteral node) {
    // ignored
  }

  @override
  visitSwitchStatement(SwitchStatement node) {
    if (entity == node.expression) {
      _addExpressionKeywords(node);
    } else if (entity == node.rightBracket) {
      if (node.members.isEmpty) {
        _addSuggestions([Keyword.CASE, Keyword.DEFAULT], DART_RELEVANCE_HIGH);
      } else {
        _addSuggestions([Keyword.CASE, Keyword.DEFAULT]);
        _addStatementKeywords(node);
      }
    }
    if (node.members.contains(entity)) {
      if (entity == node.members.first) {
        _addSuggestions([Keyword.CASE, Keyword.DEFAULT], DART_RELEVANCE_HIGH);
      } else {
        _addSuggestions([Keyword.CASE, Keyword.DEFAULT]);
        _addStatementKeywords(node);
      }
    }
  }

  @override
  visitVariableDeclaration(VariableDeclaration node) {
    if (entity == node.initializer) {
      _addExpressionKeywords(node);
    }
  }

  void _addClassBodyKeywords() {
    _addSuggestions([
      Keyword.CONST,
      Keyword.DYNAMIC,
      Keyword.FACTORY,
      Keyword.FINAL,
      Keyword.GET,
      Keyword.OPERATOR,
      Keyword.SET,
      Keyword.STATIC,
      Keyword.VAR,
      Keyword.VOID
    ]);
  }

  void _addClassDeclarationKeywords(ClassDeclaration node) {
    // Very simplistic suggestion because analyzer will warn if
    // the extends / with / implements keywords are out of order
    if (node.extendsClause == null) {
      _addSuggestion(Keyword.EXTENDS, DART_RELEVANCE_HIGH);
    } else if (node.withClause == null) {
      _addSuggestion(Keyword.WITH, DART_RELEVANCE_HIGH);
    }
    if (node.implementsClause == null) {
      _addSuggestion(Keyword.IMPLEMENTS, DART_RELEVANCE_HIGH);
    }
  }

  void _addCompilationUnitKeywords() {
    _addSuggestions([
      Keyword.ABSTRACT,
      Keyword.CLASS,
      Keyword.CONST,
      Keyword.DYNAMIC,
      Keyword.FINAL,
      Keyword.TYPEDEF,
      Keyword.VAR,
      Keyword.VOID
    ], DART_RELEVANCE_HIGH);
  }

  void _addExpressionKeywords(AstNode node) {
    _addSuggestions([
      Keyword.CONST,
      Keyword.FALSE,
      Keyword.NEW,
      Keyword.NULL,
      Keyword.TRUE,
    ]);
    if (_inClassMemberBody(node)) {
      _addSuggestions([Keyword.SUPER, Keyword.THIS,]);
    }
    if (_inAsyncMethodOrFunction(node)) {
      _addSuggestion2(AWAIT);
    }
  }

  void _addImportDirectiveKeywords(ImportDirective node) {
    bool hasDeferredKeyword = node.deferredKeyword != null;
    bool hasAsKeyword = node.asKeyword != null;
    if (!hasAsKeyword) {
      _addSuggestion(Keyword.AS, DART_RELEVANCE_HIGH);
    }
    if (!hasDeferredKeyword) {
      if (!hasAsKeyword) {
        _addSuggestion2('deferred as', relevance: DART_RELEVANCE_HIGH);
      } else if (entity == node.asKeyword) {
        _addSuggestion(Keyword.DEFERRED, DART_RELEVANCE_HIGH);
      }
    }
    if (!hasDeferredKeyword || hasAsKeyword) {
      if (node.combinators.isEmpty) {
        _addSuggestion2('show', relevance: DART_RELEVANCE_HIGH);
        _addSuggestion2('hide', relevance: DART_RELEVANCE_HIGH);
      }
    }
  }

  void _addStatementKeywords(AstNode node) {
    if (_inClassMemberBody(node)) {
      _addSuggestions([Keyword.SUPER, Keyword.THIS,]);
    }
    if (_inAsyncMethodOrFunction(node)) {
      _addSuggestion2(AWAIT);
    }
    if (_inLoop(node)) {
      _addSuggestions([Keyword.BREAK, Keyword.CONTINUE]);
    }
    if (_inSwitch(node)) {
      _addSuggestions([Keyword.BREAK]);
    }
    _addSuggestions([
      Keyword.ASSERT,
      Keyword.CONST,
      Keyword.DO,
      Keyword.FINAL,
      Keyword.FOR,
      Keyword.IF,
      Keyword.NEW,
      Keyword.RETURN,
      Keyword.SWITCH,
      Keyword.THROW,
      Keyword.TRY,
      Keyword.VAR,
      Keyword.VOID,
      Keyword.WHILE
    ]);
  }

  void _addSuggestion(Keyword keyword,
      [int relevance = DART_RELEVANCE_KEYWORD]) {
    _addSuggestion2(keyword.syntax, relevance: relevance);
  }

  void _addSuggestion2(String completion,
      {int offset, int relevance: DART_RELEVANCE_KEYWORD}) {
    if (offset == null) {
      offset = completion.length;
    }
    suggestions.add(new CompletionSuggestion(CompletionSuggestionKind.KEYWORD,
        relevance, completion, offset, 0, false, false));
  }

  void _addSuggestions(List<Keyword> keywords,
      [int relevance = DART_RELEVANCE_KEYWORD]) {
    keywords.forEach((Keyword keyword) {
      _addSuggestion(keyword, relevance);
    });
  }

  bool _inAsyncMethodOrFunction(AstNode node) {
    FunctionBody body = node.getAncestor((n) => n is FunctionBody);
    return body != null && body.isAsynchronous;
  }

  bool _inCatchClause(Block node) =>
      node.getAncestor((p) => p is CatchClause) != null;

  bool _inClassMemberBody(AstNode node) {
    while (true) {
      AstNode body = node.getAncestor((n) => n is FunctionBody);
      if (body == null) {
        return false;
      }
      AstNode parent = body.parent;
      if (parent is ConstructorDeclaration || parent is MethodDeclaration) {
        return true;
      }
      node = parent;
    }
  }

  bool _inDoLoop(AstNode node) =>
      node.getAncestor((p) => p is DoStatement) != null;

  bool _inForLoop(AstNode node) =>
      node.getAncestor((p) => p is ForStatement || p is ForEachStatement) !=
          null;

  bool _inLoop(AstNode node) =>
      _inDoLoop(node) || _inForLoop(node) || _inWhileLoop(node);

  bool _inSwitch(AstNode node) =>
      node.getAncestor((p) => p is SwitchStatement) != null;

  bool _inWhileLoop(AstNode node) =>
      node.getAncestor((p) => p is WhileStatement) != null;
}
