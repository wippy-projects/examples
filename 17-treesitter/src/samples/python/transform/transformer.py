from formatter import format_date, format_currency
from logger_util import log_info


def transform_records(records):
    log_info(f"Transforming {len(records)} records")
    result = []
    for record in records:
        transformed = apply_transforms(record)
        result.append(transformed)
    return result


def apply_transforms(record):
    record = normalize_fields(record)
    record = enrich_record(record)
    return record


def normalize_fields(record):
    return format_date(str(record))


def enrich_record(record):
    return format_currency(str(record))
