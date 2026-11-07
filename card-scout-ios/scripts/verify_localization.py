#!/usr/bin/env python3
"""Check both shipped UI languages, placeholder safety and presentation coverage."""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def strings(path):
    result = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith('/*'): continue
        match = re.fullmatch(r'("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");', line)
        if not match: raise AssertionError(f'Invalid strings syntax: {path}: {line}')
        key, value = map(json.loads, match.groups())
        if key in result: raise AssertionError(f'Duplicate key: {key}')
        result[key] = value
    return result

def literal(source, start):
    index = start + 1; result = ''; arguments = 0
    while index < len(source):
        char = source[index]
        if char == '"': return index + 1, result
        if char == '\\':
            if source[index + 1] == '(':
                index += 2; depth = 1
                while depth:
                    if source[index] == '"': index, _ = literal(source, index); continue
                    if source[index] == '(': depth += 1
                    if source[index] == ')': depth -= 1
                    index += 1
                arguments += 1; result += f'%{arguments}$@'; continue
            code = source[index:index + 2]
            result += {'\\n': '\n', '\\t': '\t', '\\r': '\r', '\\"': '"', '\\\\': '\\'}.get(code, code)
            index += 2; continue
        result += '%%' if char == '%' else char; index += 1
    raise AssertionError('Unclosed Swift string')

def main():
    de = strings(ROOT / 'App/de.lproj/Localizable.strings')
    en = strings(ROOT / 'App/en.lproj/Localizable.strings')
    assert de.keys() == en.keys(), 'Language key sets differ'
    errors = []
    for key in de:
        expected = set(re.findall(r'%([0-9]+)\$@', key))
        for language, table in [('de', de), ('en', en)]:
            actual = set(re.findall(r'%([0-9]+)\$@', table[key]))
            if not actual <= expected: errors.append(f'{language}: invalid interpolation in {key}')
    for path in (ROOT / 'App').glob('*.swift'):
        if path.name == 'PreviewData.swift': continue
        source = path.read_text()
        for match in re.finditer(r'\btr\((")', source):
            _, key = literal(source, match.end() - 1)
            # Formatting-only strings have no translatable text.
            visible = re.sub(r'%[0-9]+\$@', '', key)
            if re.search(r'[A-Za-zÄÖÜäöüß]', visible) and key not in en:
                errors.append(f'{path.name}: missing translation: {key}')
        for match in re.finditer(r'\b(Text|Label|Button|navigationTitle|accessibilityLabel|accessibilityHint|DisclosureGroup)\((")', source):
            _, key = literal(source, match.end() - 1)
            if key not in ['Deutsch', 'English']:
                errors.append(f'{path.name}: untranslated UI literal: {key}')
    templates = json.loads((ROOT / 'App/LocalizableTemplates.json').read_text())
    assert all(key in en for key in templates)
    if errors:
        print('\n'.join(errors)); return 1
    print(f'Localization audit passed: {len(en)} bilingual keys, {len(templates)} dynamic label templates.')
    return 0

if __name__ == '__main__': sys.exit(main())
