#!/usr/bin/python2.6
#
# Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Generates CSSStyleDeclaration from css property definitions defined in WebKit."""

import tempfile, os

COMMENT_LINE_PREFIX = '   * '
SOURCE_PATH = 'Source/WebCore/css/CSSPropertyNames.in'
INPUT_URL = 'http://trac.webkit.org/export/latest/trunk/%s' % SOURCE_PATH
INTERFACE_FILE = '../../html/src/CSSStyleDeclaration.dart'
CLASS_FILE = '../../html/src/CSSStyleDeclarationWrappingImplementation.dart'

def main():
  _, css_names_file = tempfile.mkstemp('.CSSPropertyNames.in')
  try:
    if os.system('wget %s -O %s' % (INPUT_URL, css_names_file)):
      return 1
    generate_code(css_names_file)
    print 'Successfully generated %s and %s' % (INTERFACE_FILE, CLASS_FILE)
  finally:
    os.remove(css_names_file)

def camelCaseName(name):
  """Convert a CSS property name to a lowerCamelCase name."""
  name = name.replace('-webkit-', '')
  words = []
  for word in name.split('-'):
    if words:
      words.append(word.title())
    else:
      words.append(word)
  return ''.join(words)

def generate_code(input_path):
  data = open(input_path).readlines()

  # filter CSSPropertyNames.in to only the properties
  data = [d[:-1] for d in data
          if len(d) > 1
          and not d.startswith('#')
          and not d.startswith('//')
          and not '=' in d]

  interface_file = open(INTERFACE_FILE, 'w')
  class_file = open(CLASS_FILE, 'w')

  interface_file.write("""
// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// WARNING: Do not edit.
// This file was generated by html/scripts/css_code_generator.py

// Source of CSS properties:
//   %s

// TODO(jacobr): add versions that take numeric values in px, miliseconds, etc.

interface CSSStyleDeclaration {

  String get cssText;

  void set cssText(String value);

  int get length;

  CSSRule get parentRule;

  CSSValue getPropertyCSSValue(String propertyName);

  String getPropertyPriority(String propertyName);

  String getPropertyShorthand(String propertyName);

  String getPropertyValue(String propertyName);

  bool isPropertyImplicit(String propertyName);

  String item(int index);

  String removeProperty(String propertyName);

  void setProperty(String propertyName, String value, [String priority]);

""".lstrip() % SOURCE_PATH)


  class_file.write("""
// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// WARNING: Do not edit.
// This file was generated by html/scripts/css_code_generator.py

// Source of CSS properties:
//   %s

// TODO(jacobr): add versions that take numeric values in px, miliseconds, etc.

class CSSStyleDeclarationWrappingImplementation extends DOMWrapperBase implements CSSStyleDeclaration {
  static String _cachedBrowserPrefix;

  CSSStyleDeclarationWrappingImplementation._wrap(ptr) : super._wrap(ptr) {}

  static String get _browserPrefix {
    if (_cachedBrowserPrefix == null) {
      if (_Device.isFirefox) {
        _cachedBrowserPrefix = '-moz-';
      } else {
        _cachedBrowserPrefix = '-webkit-';
      }
      // TODO(jacobr): support IE 9.0 and Opera as well.
    }
    return _cachedBrowserPrefix;
  }

  String get cssText { return _ptr.cssText; }

  void set cssText(String value) { _ptr.cssText = value; }

  int get length { return _ptr.length; }

  CSSRule get parentRule { return LevelDom.wrapCSSRule(_ptr.parentRule); }

  CSSValue getPropertyCSSValue(String propertyName) {
    return LevelDom.wrapCSSValue(_ptr.getPropertyCSSValue(propertyName));
  }

  String getPropertyPriority(String propertyName) {
    return _ptr.getPropertyPriority(propertyName);
  }

  String getPropertyShorthand(String propertyName) {
    return _ptr.getPropertyShorthand(propertyName);
  }

  String getPropertyValue(String propertyName) {
    return _ptr.getPropertyValue(propertyName);
  }

  bool isPropertyImplicit(String propertyName) {
    return _ptr.isPropertyImplicit(propertyName);
  }

  String item(int index) {
    return _ptr.item(index);
  }

  String removeProperty(String propertyName) {
    return _ptr.removeProperty(propertyName);
  }

  void setProperty(String propertyName, String value, [String priority = '']) {
    _ptr.setProperty(propertyName, value, priority);
  }

  String get typeName { return "CSSStyleDeclaration"; }

""".lstrip() % SOURCE_PATH)

  interface_lines = [];
  class_lines = [];

  seen = set()
  for prop in sorted(data, key=lambda p: camelCaseName(p)):
    camel_case_name = camelCaseName(prop)
    upper_camel_case_name = camel_case_name[0].upper() + camel_case_name[1:];
    css_name = prop.replace('-webkit-', '${_browserPrefix}')
    base_css_name = prop.replace('-webkit-', '')

    if base_css_name in seen:
      continue
    seen.add(base_css_name)

    comment = '  /** %s the value of "' + base_css_name + '" */'

    interface_lines.append(comment % 'Gets')
    interface_lines.append("""
  String get %s;

""" % camel_case_name)

    interface_lines.append(comment % 'Sets')
    interface_lines.append("""
  void set %s(String value);

""" % camel_case_name)

    class_lines.append('\n');
    class_lines.append(comment % 'Gets')
    class_lines.append("""
  String get %s =>
    getPropertyValue('%s');

""" % (camel_case_name, css_name))

    class_lines.append(comment % 'Sets')
    class_lines.append("""
  void set %s(String value) {
    setProperty('%s', value, '');
  }
""" % (camel_case_name, css_name))

  interface_file.write(''.join(interface_lines));
  interface_file.write('}\n')
  interface_file.close()

  class_file.write(''.join(class_lines));
  class_file.write('}\n')
  class_file.close()

if __name__ == '__main__':
  main()