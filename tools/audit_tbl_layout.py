#!/usr/bin/env python3
"""Read-only source-7 audit; no JSON data is regenerated.

Usage: python tools/audit_tbl_layout.py ORIGINAL_TBL_DIR HISTORICAL_JSON_DIR NF_JSON_DIR OUTPUT.json
NF exports are produced by tools/spell4_reference_reader; all paths are inputs
except OUTPUT, which must be inside the current workspace. Standard library only.
"""
import hashlib
import importlib.util
import json
import re
import struct
import sys
from pathlib import Path


def main():
    table_dir, json_dir, nf_dir, output = map(Path, sys.argv[1:])
    output.resolve().relative_to(Path.cwd().resolve())
    if output.suffix != '.json':
        raise ValueError('workspace JSON output required')
    module_path = Path(__file__).parent / 'tbl_extractor' / 'tbl_extractor.py'
    spec = importlib.util.spec_from_file_location('tbl_layout_reader', module_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    candidates, failures = [], []
    total = 0
    for path in sorted(table_dir.glob('*.tbl')):
        total += 1
        reader = module.TblExtractor(str(path))
        try:
            reader._data = path.read_bytes()
            reader._read_header()
            reader._read_fields()
            if not any(f.data_type == 130 and n.data_type != 130
                       for f, n in zip(reader.fields, reader.fields[1:])):
                continue
            affected = 0
            first = None
            for row in range(reader.header.record_count):
                offset = 96 + reader.header.record_offset + row * reader.header.record_size
                padded = False
                for index, field in enumerate(reader.fields):
                    if field.data_type == 130:
                        zero = struct.unpack_from('<I', reader._data, offset)[0] == 0
                        offset += 8
                        if zero and index + 1 < len(reader.fields) and reader.fields[index+1].data_type != 130:
                            offset += 4
                            padded = True
                            if first is None:
                                first = {'record_index': row, 'after_field': field.name,
                                         'following_field': reader.fields[index+1].name}
                    elif field.data_type in (3, 4, 11):
                        offset += 4
                    elif field.data_type == 20:
                        offset += 8
                    else:
                        raise ValueError(f'unknown field type {field.data_type}')
                affected += int(padded)
            files = sorted(p.name for p in json_dir.glob('*.json')
                           if re.sub(r'_part\d+$', '', p.stem).lower() == path.stem.lower())
            candidates.append({'table': path.stem, 'rows': reader.header.record_count,
                               'rows_with_padding': affected, 'first_padding': first,
                               'historical_files': files,
                               'sha256': hashlib.sha256(reader._data).hexdigest()})
        except (ValueError, struct.error) as exc:
            failures.append({'table': path.stem, 'error': str(exc)})

    historical = []
    for candidate in candidates:
        if not candidate['historical_files'] or not candidate['rows_with_padding']:
            continue
        name = candidate['table']
        rows = module.TblExtractor(str(table_dir / (name + '.tbl'))).extract()
        corrected = {row['ID']: row for row in rows}
        mismatched = 0
        rounding_only = 0
        examples = []
        compared = 0
        for filename in candidate['historical_files']:
            data = json.loads((json_dir / filename).read_text(encoding='utf-8-sig'))
            old_rows = data if isinstance(data, list) else next(iter(data.values()))
            for old in old_rows:
                compared += 1
                new = corrected.get(old['ID'])
                if new is None:
                    raise ValueError(f'historical ID missing in original {name}: {old["ID"]}')
                differences = [(key, old.get(key), value) for key, value in new.items()
                               if old.get(key) != value]
                structural = [(key, a, b) for key, a, b in differences
                              if not (isinstance(b, float) and a == round(b, 6))]
                mismatched += int(bool(structural))
                rounding_only += int(bool(differences) and not structural)
                if len(examples) < 12:
                    examples.extend({'id': old['ID'], 'field': key, 'historical': a, 'original': b}
                                    for key, a, b in structural[:12-len(examples)])
        historical.append({'table': name, 'rows_compared': compared,
                           'rows_with_structural_differences': mismatched,
                           'rows_with_only_rounding_differences': rounding_only,
                           'first_differences': examples})

    comparisons = []
    for nf_path in sorted(nf_dir.glob('nf-*.json')):
        name = nf_path.stem.removeprefix('nf-')
        path = table_dir / (name + '.tbl')
        actual = module.TblExtractor(str(path)).extract()
        expected = json.loads(nf_path.read_text(encoding='utf-8-sig'))
        if actual != expected:
            raise ValueError(f'Corrected Python reader differs from NexusForever: {name}')
        comparisons.append({'table': name, 'rows_compared': len(actual), 'equal': True})

    result = {'tables_scanned': total, 'string_before_scalar_tables': candidates,
              'scan_failures': failures, 'corrected_python_vs_nexusforever': comparisons,
              'historical_json_comparisons': historical,
              'json_regenerated': [], 'notes': [
                  'Padding counts are binary observations, not proof of which historical extractor produced each JSON.',
                  'Six-decimal rounding is a separate historical precision loss; corrected reader preserves float32.',
                  'No production data or original tables are written.']}
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f'{total} tables scanned; {len(candidates)} string/scalar schemas; {len(failures)} failures; '
          f'{len(comparisons)} complete Python/NexusForever comparisons')


if __name__ == '__main__':
    main()
