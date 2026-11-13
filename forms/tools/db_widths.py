"""Column type and width from db/01_tables.sql (CREATE TABLE only; views are not resolved here).

Shared by gen_forms_xml.py (item MaximumLength) and check_refs.py (static check), so the widths the
forms use always come from the same DDL. Returns {(table, column): (type, width_or_None)}, lower case.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DDL = os.path.join(ROOT, "db", "01_tables.sql")
COL = re.compile(r"^\s*(\w+)\s+(VARCHAR2|NVARCHAR2|CHAR|NCHAR|NUMBER|DATE|TIMESTAMP|CLOB)\b(\((\d+)[^)]*\))?",
                 re.I)


def load(path=DDL):
    cols = {}
    table = None
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if line.lstrip().startswith("--"):
                continue
            m = re.match(r"\s*CREATE\s+TABLE\s+(\w+)\s*\(", line, re.I)
            if m:
                table = m.group(1).lower()
                continue
            if table and re.match(r"\s*\)\s*;", line):
                table = None
                continue
            if table:
                c = COL.match(line)
                if c and c.group(1).upper() not in ("CONSTRAINT", "PRIMARY", "UNIQUE", "CHECK", "FOREIGN"):
                    width = int(c.group(4)) if c.group(4) else None
                    cols[(table, c.group(1).lower())] = (c.group(2).upper(), width)
    return cols


if __name__ == "__main__":
    d = load()
    print("%d table columns parsed" % len(d))
