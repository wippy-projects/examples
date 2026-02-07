from cache import get_cached, set_cached
from logger_util import log_info


def load_csv(path):
    cached = get_cached(path)
    if cached:
        return cached
    data = read_file(path)
    records = parse_csv(data)
    set_cached(path, records)
    log_info(f"Loaded {len(records)} from CSV")
    return records


def load_json(path):
    cached = get_cached(path)
    if cached:
        return cached
    data = read_file(path)
    records = parse_json(data)
    set_cached(path, records)
    log_info(f"Loaded {len(records)} from JSON")
    return records


def read_file(path):
    return ""


def parse_csv(data):
    return data.split("\n")


def parse_json(data):
    return [data]
