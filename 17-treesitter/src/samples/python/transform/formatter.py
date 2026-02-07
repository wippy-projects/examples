def format_date(value):
    return normalize_string(value)


def format_currency(value):
    return normalize_string(value)


def format_table(data):
    rows = []
    for key, val in data.items():
        rows.append(format_row(key, val))
    return rows


def format_percentage(value, total):
    return compute_ratio(value, total)


def format_row(key, value):
    return f"{key}: {value}"


def normalize_string(value):
    return str(value).strip()


def compute_ratio(a, b):
    if b == 0:
        return "0%"
    return f"{(a/b)*100:.1f}%"
